require "../spec_helper"
require "openapi/form/serializable"

struct TestForm
  include OpenAPI::Form::Serializable

  getter name : String
  getter count : Int32
  getter weight : Float64?

  def initialize(@name, @count, @weight = nil)
  end
end

struct TestFormAnnotated
  include OpenAPI::Form::Serializable

  @[OpenAPI::Form::Field(key: "full_name")]
  getter name : String

  def initialize(@name)
  end
end

struct TestAddress
  include OpenAPI::Form::Serializable

  getter city : String
  getter zip : String?

  def initialize(@city, @zip = nil)
  end
end

struct TestWithNested
  include OpenAPI::Form::Serializable

  getter name : String
  getter address : TestAddress
  getter billing : TestAddress?

  def initialize(@name, @address, @billing = nil)
  end
end

struct TestItem
  include OpenAPI::Form::Serializable

  getter sku : String
  getter qty : Int32

  def initialize(@sku, @qty)
  end
end

struct TestWithArrays
  include OpenAPI::Form::Serializable

  getter tags : Array(String)
  getter ids : Array(Int32)?
  getter items : Array(TestItem)

  def initialize(@tags, @items, @ids = nil)
  end
end

describe OpenAPI::Form::Serializable do
  it "round-trips a struct through form encoding" do
    t = TestForm.new(name: "hello", count: 42, weight: 3.14)
    decoded = TestForm.from_form_params(HTTP::Params.parse(t.to_form_params))
    decoded.name.should eq("hello")
    decoded.count.should eq(42)
    decoded.weight.not_nil!.should be_close(3.14, 0.001)
  end

  it "omits nil optional fields from encoding" do
    t = TestForm.new(name: "x", count: 1)
    t.to_form_params.should_not contain("weight")
  end

  it "uses OpenAPI::Form::Field key annotation as wire name" do
    t = TestFormAnnotated.new(name: "Alice")
    params = HTTP::Params.parse(t.to_form_params)
    params["full_name"].should eq("Alice")
    params["name"]?.should be_nil
    TestFormAnnotated.from_form_params(params).name.should eq("Alice")
  end

  it "encodes a nested Form::Serializable object with bracket notation" do
    t = TestWithNested.new(name: "Bob", address: TestAddress.new(city: "SF", zip: "94105"))
    encoded = t.to_form_params
    params = HTTP::Params.parse(encoded)
    params["name"].should eq("Bob")
    params["address[city]"].should eq("SF")
    params["address[zip]"].should eq("94105")
    encoded.should_not contain("billing")
  end

  it "round-trips a nested Form::Serializable through form encoding" do
    t = TestWithNested.new(name: "Bob", address: TestAddress.new(city: "SF", zip: "94105"))
    decoded = TestWithNested.from_form_params(HTTP::Params.parse(t.to_form_params))
    decoded.name.should eq("Bob")
    decoded.address.city.should eq("SF")
    decoded.address.zip.should eq("94105")
  end

  it "omits nil nested Form::Serializable from output" do
    t = TestWithNested.new(name: "Bob", address: TestAddress.new(city: "LA"))
    t.to_form_params.should_not contain("billing")
  end

  it "encodes an array of scalars with [] suffix" do
    t = TestWithArrays.new(tags: ["ruby", "rails"], items: [] of TestItem)
    encoded = t.to_form_params
    params = HTTP::Params.parse(encoded)
    params.fetch_all("tags[]").should eq(["ruby", "rails"])
    encoded.should_not contain("ids")
  end

  it "round-trips an array of strings through form encoding" do
    t = TestWithArrays.new(tags: ["a", "b", "c"], items: [] of TestItem)
    decoded = TestWithArrays.from_form_params(HTTP::Params.parse(t.to_form_params))
    decoded.tags.should eq(["a", "b", "c"])
  end

  it "encodes an array of Form::Serializable with indexed bracket notation" do
    t = TestWithArrays.new(
      tags: [] of String,
      items: [TestItem.new(sku: "ABC", qty: 2), TestItem.new(sku: "DEF", qty: 5)]
    )
    params = HTTP::Params.parse(t.to_form_params)
    params["items[0][sku]"].should eq("ABC")
    params["items[0][qty]"].should eq("2")
    params["items[1][sku]"].should eq("DEF")
    params["items[1][qty]"].should eq("5")
  end
end
