require "../spec_helper"
require "openapi/xml/serializable"

struct TestXml
  include OpenAPI::XML::Serializable

  getter name : String
  getter count : Int32
  getter weight : Float64?

  def initialize(@name, @count, @weight = nil)
  end
end

struct TestXmlAnnotated
  include OpenAPI::XML::Serializable

  @[OpenAPI::XML::Field(key: "full_name")]
  getter name : String

  def initialize(@name)
  end
end

struct TestXmlJsonKey
  include OpenAPI::XML::Serializable

  @[JSON::Field(key: "full_name")]
  getter name : String

  def initialize(@name)
  end
end

struct TestXmlAddress
  include OpenAPI::XML::Serializable

  getter city : String
  getter zip : String?

  def initialize(@city, @zip = nil)
  end
end

struct TestXmlNested
  include OpenAPI::XML::Serializable

  getter label : String
  getter address : TestXmlAddress
  getter billing : TestXmlAddress?

  def initialize(@label, @address, @billing = nil)
  end
end

struct TestXmlAllTypes
  include OpenAPI::XML::Serializable

  getter s : String
  getter i32 : Int32
  getter i64 : Int64
  getter f32 : Float32
  getter f64 : Float64
  getter? flag : Bool

  def initialize(@s, @i32, @i64, @f32, @f64, @flag)
  end
end

struct TestXmlItem
  include OpenAPI::XML::Serializable

  getter sku : String

  def initialize(@sku)
  end
end

struct TestXmlAttr
  include OpenAPI::XML::Serializable

  @[OpenAPI::XML::Field(attribute: true)]
  getter id : Int32

  getter name : String

  def initialize(@id, @name)
  end
end

struct TestXmlAttrKey
  include OpenAPI::XML::Serializable

  @[OpenAPI::XML::Field(attribute: true, key: "uid")]
  getter id : Int32

  def initialize(@id)
  end
end

struct TestXmlWrapped
  include OpenAPI::XML::Serializable

  @[OpenAPI::XML::Field(wrapped: true, item_key: "tag")]
  getter tags : Array(String)

  def initialize(@tags)
  end
end

struct TestXmlWrappedObjects
  include OpenAPI::XML::Serializable

  @[OpenAPI::XML::Field(wrapped: true)]
  getter items : Array(TestXmlItem)

  def initialize(@items)
  end
end

struct TestXmlUnwrapped
  include OpenAPI::XML::Serializable

  @[OpenAPI::XML::Field(item_key: "entry")]
  getter entries : Array(String)

  def initialize(@entries)
  end
end

@[OpenAPI::XML::Element(name: "animal")]
struct TestXmlElementName
  include OpenAPI::XML::Serializable

  getter kind : String

  def initialize(@kind)
  end
end

describe OpenAPI::XML::Serializable do
  it "round-trips all scalar types" do
    orig = TestXmlAllTypes.new(s: "hello", i32: 1, i64: 2_i64, f32: 1.5_f32, f64: 3.14, flag: true)
    rt = TestXmlAllTypes.from_xml(orig.to_xml)
    rt.s.should eq("hello")
    rt.i32.should eq(1)
    rt.i64.should eq(2_i64)
    rt.f32.should be_close(1.5_f32, 0.001)
    rt.f64.should be_close(3.14, 0.001)
    rt.flag?.should eq(true)
  end

  it "round-trips a struct with an optional field present" do
    orig = TestXml.new(name: "Alice", count: 7, weight: 2.5)
    rt = TestXml.from_xml(orig.to_xml)
    rt.name.should eq("Alice")
    rt.count.should eq(7)
    rt.weight.not_nil!.should be_close(2.5, 0.001)
  end

  it "omits nil optional field from output" do
    t = TestXml.new(name: "Bob", count: 3)
    t.to_xml.should_not contain("<weight>")
  end

  it "includes present optional field in output" do
    t = TestXml.new(name: "Bob", count: 3, weight: 3.14)
    t.to_xml.should contain("<weight>")
  end

  it "xml_element_name returns the unqualified type name downcased" do
    TestXml.xml_element_name.should eq("testxml")
    TestXmlAddress.xml_element_name.should eq("testxmladdress")
  end

  it "uses OpenAPI::XML::Field key annotation as the wire element name" do
    t = TestXmlAnnotated.new(name: "Carol")
    xml = t.to_xml
    xml.should contain("<full_name>Carol</full_name>")
    xml.should_not contain("<name>")
    TestXmlAnnotated.from_xml(xml).name.should eq("Carol")
  end

  it "falls back to JSON::Field key annotation as the wire element name" do
    t = TestXmlJsonKey.new(name: "Dave")
    xml = t.to_xml
    xml.should contain("<full_name>Dave</full_name>")
    xml.should_not contain("<name>")
    TestXmlJsonKey.from_xml(xml).name.should eq("Dave")
  end

  it "round-trips a nested XML::Serializable struct" do
    orig = TestXmlNested.new(
      label: "home",
      address: TestXmlAddress.new(city: "Berlin", zip: "10115"),
      billing: TestXmlAddress.new(city: "Munich"),
    )
    rt = TestXmlNested.from_xml(orig.to_xml)
    rt.label.should eq("home")
    rt.address.city.should eq("Berlin")
    rt.address.zip.should eq("10115")
    rt.billing.not_nil!.city.should eq("Munich")
  end

  it "omits nil nested struct from output" do
    t = TestXmlNested.new(label: "work", address: TestXmlAddress.new(city: "Paris"))
    t.to_xml.should_not contain("<billing>")
  end

  it "accepts IO as input to from_xml" do
    xml = TestXml.new(name: "Eve", count: 5).to_xml
    rt = TestXml.from_xml(IO::Memory.new(xml))
    rt.name.should eq("Eve")
    rt.count.should eq(5)
  end

  it "Array(T).to_xml wraps items in a plural root element" do
    items = [TestXmlItem.new(sku: "A1"), TestXmlItem.new(sku: "B2")]
    xml = items.to_xml
    xml.should contain("<testxmlitems>")
    xml.should contain("<testxmlitem>")
    xml.should contain("<sku>A1</sku>")
    xml.should contain("<sku>B2</sku>")
  end

  it "Array(T).from_xml round-trips a list of items" do
    items = [TestXmlItem.new(sku: "X"), TestXmlItem.new(sku: "Y"), TestXmlItem.new(sku: "Z")]
    rt = Array(TestXmlItem).from_xml(items.to_xml)
    rt.size.should eq(3)
    rt.map(&.sku).should eq(["X", "Y", "Z"])
  end

  it "Array(T).from_xml round-trips an empty array" do
    rt = Array(TestXmlItem).from_xml(Array(TestXmlItem).new.to_xml)
    rt.should be_empty
  end

  # ── XML attributes ──────────────────────────────────────────────────────────

  it "attribute: true serializes as an XML attribute, not a child element" do
    xml = TestXmlAttr.new(id: 42, name: "Rex").to_xml
    xml.should contain("id=\"42\"")
    xml.should_not contain("<id>")
    xml.should contain("<name>Rex</name>")
  end

  it "attribute: true round-trips via from_xml" do
    orig = TestXmlAttr.new(id: 7, name: "Spot")
    rt = TestXmlAttr.from_xml(orig.to_xml)
    rt.id.should eq(7)
    rt.name.should eq("Spot")
  end

  it "attribute: true with key: uses the annotation key as the attribute name" do
    xml = TestXmlAttrKey.new(id: 99).to_xml
    xml.should contain("uid=\"99\"")
    xml.should_not contain(" id=")
    TestXmlAttrKey.from_xml(xml).id.should eq(99)
  end

  # ── Wrapped arrays ──────────────────────────────────────────────────────────

  it "wrapped: true wraps scalar items in an outer element" do
    xml = TestXmlWrapped.new(tags: ["a", "b", "c"]).to_xml
    xml.should contain("<tags>")
    xml.should contain("<tag>a</tag>")
    xml.should contain("<tag>b</tag>")
    xml.should contain("<tag>c</tag>")
  end

  it "wrapped: true round-trips scalar array" do
    orig = TestXmlWrapped.new(tags: ["x", "y"])
    rt = TestXmlWrapped.from_xml(orig.to_xml)
    rt.tags.should eq(["x", "y"])
  end

  it "wrapped: true wraps XML::Serializable items using their element name" do
    xml = TestXmlWrappedObjects.new(items: [TestXmlItem.new(sku: "A"), TestXmlItem.new(sku: "B")]).to_xml
    xml.should contain("<items>")
    xml.should contain("<testxmlitem>")
    xml.should contain("<sku>A</sku>")
  end

  it "wrapped: true round-trips XML::Serializable items" do
    orig = TestXmlWrappedObjects.new(items: [TestXmlItem.new(sku: "P"), TestXmlItem.new(sku: "Q")])
    rt = TestXmlWrappedObjects.from_xml(orig.to_xml)
    rt.items.size.should eq(2)
    rt.items.map(&.sku).should eq(["P", "Q"])
  end

  # ── Unwrapped arrays ────────────────────────────────────────────────────────

  it "array without wrapped emits items directly as siblings" do
    xml = TestXmlUnwrapped.new(entries: ["one", "two"]).to_xml
    xml.should_not contain("<entries>")
    xml.should contain("<entry>one</entry>")
    xml.should contain("<entry>two</entry>")
  end

  it "unwrapped array round-trips" do
    orig = TestXmlUnwrapped.new(entries: ["foo", "bar"])
    rt = TestXmlUnwrapped.from_xml(orig.to_xml)
    rt.entries.should eq(["foo", "bar"])
  end

  # ── @[OpenAPI::XML::Element] ─────────────────────────────────────────────────

  it "@[OpenAPI::XML::Element(name:)] overrides xml_element_name" do
    TestXmlElementName.xml_element_name.should eq("animal")
  end

  it "@[OpenAPI::XML::Element(name:)] is used as the root element in to_xml" do
    xml = TestXmlElementName.new(kind: "dog").to_xml
    xml.should contain("<animal>")
    xml.should_not contain("<testxmlelementname>")
  end

  it "@[OpenAPI::XML::Element(name:)] round-trips via from_xml" do
    orig = TestXmlElementName.new(kind: "cat")
    rt = TestXmlElementName.from_xml(orig.to_xml)
    rt.kind.should eq("cat")
  end
end
