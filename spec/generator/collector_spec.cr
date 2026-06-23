require "../spec_helper"

describe OpenAPI::Generator::Types::Collector do
  it "collects schemas from Petstore" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
    schemas = OpenAPI::Generator::Types::Collector.collect(doc, OpenAPI::Generator::Types::DefaultHooks.new)
    names = schemas.map(&.name)
    names.should contain("Pet")
    names.should contain("Error")
  end

  it "classifies Pet as Class" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
    schemas = OpenAPI::Generator::Types::Collector.collect(doc, OpenAPI::Generator::Types::DefaultHooks.new)
    pet = schemas.find! { |cs| cs.name == "Pet" }
    pet.kind.should eq(OpenAPI::Generator::Types::SchemaKind::Class)
  end
end

describe "composition keyword classification" do
  it "classifies all-refs oneOf (2+) as UnionAlias" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    schemas = OpenAPI::Generator::Types::Collector.collect(doc, OpenAPI::Generator::Types::DefaultHooks.new)
    s = schemas.find! { |cs| cs.name == "ResourceOrEvent" }
    s.kind.should eq(OpenAPI::Generator::Types::SchemaKind::UnionAlias)
  end

  it "classifies all-refs anyOf (2+) as UnionAlias" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    schemas = OpenAPI::Generator::Types::Collector.collect(doc, OpenAPI::Generator::Types::DefaultHooks.new)
    s = schemas.find! { |cs| cs.name == "ScalarValue" }
    s.kind.should eq(OpenAPI::Generator::Types::SchemaKind::UnionAlias)
  end

  it "classifies single-ref oneOf as ScalarAlias" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    schemas = OpenAPI::Generator::Types::Collector.collect(doc, OpenAPI::Generator::Types::DefaultHooks.new)
    s = schemas.find! { |cs| cs.name == "SingleResource" }
    s.kind.should eq(OpenAPI::Generator::Types::SchemaKind::ScalarAlias)
  end

  it "classifies mixed inline+ref anyOf as AnyAlias" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    schemas = OpenAPI::Generator::Types::Collector.collect(doc, OpenAPI::Generator::Types::DefaultHooks.new)
    s = schemas.find! { |cs| cs.name == "FlexPayload" }
    s.kind.should eq(OpenAPI::Generator::Types::SchemaKind::AnyAlias)
  end

  it "classifies single-ref allOf (no extra props) as ScalarAlias" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    schemas = OpenAPI::Generator::Types::Collector.collect(doc, OpenAPI::Generator::Types::DefaultHooks.new)
    s = schemas.find! { |cs| cs.name == "AliasedResource" }
    s.kind.should eq(OpenAPI::Generator::Types::SchemaKind::ScalarAlias)
  end

  it "classifies all-refs allOf (2+) as ComposeAlias" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    schemas = OpenAPI::Generator::Types::Collector.collect(doc, OpenAPI::Generator::Types::DefaultHooks.new)
    s = schemas.find! { |cs| cs.name == "AnnotatedResource" }
    s.kind.should eq(OpenAPI::Generator::Types::SchemaKind::ComposeAlias)
  end

  it "classifies oneOf with discriminator as AbstractClass" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    schemas = OpenAPI::Generator::Types::Collector.collect(doc, OpenAPI::Generator::Types::DefaultHooks.new)
    s = schemas.find! { |cs| cs.name == "Event" }
    s.kind.should eq(OpenAPI::Generator::Types::SchemaKind::AbstractClass)
  end
end

describe "composition code generation" do
  it "generates openapi_union macro call for oneOf with explicit discriminator mapping" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should_not contain("abstract class Event")
    content.should contain("openapi_union Event, {CreatedEvent, UpdatedEvent},")
    content.should contain(%(discriminator: "event_type",))
    content.should contain(%(mapping: {"resource.created" => CreatedEvent, "resource.updated" => UpdatedEvent}))
    content.should contain(%(require "openapi/macro/union"))
  end

  it "generates openapi_union macro call for oneOf with implicit discriminator mapping" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("openapi_union ImplicitEvent, {CreatedEvent, UpdatedEvent},")
    content.should contain(%(discriminator: "event_type",))
    content.should contain(%(mapping: {"CreatedEvent" => CreatedEvent, "UpdatedEvent" => UpdatedEvent}))
  end

  it "generates openapi_union macro call for UnionAlias (oneOf all-refs)" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("openapi_union ResourceOrEvent, {Resource, BaseEvent}")
    content.should contain("openapi_union ScalarValue, {StringValue, IntValue, BoolValue}")
  end

  it "generates openapi_allof macro call for allOf all-refs" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("openapi_allof AnnotatedResource, {Resource, Metadata}")
    content.should contain(%(require "openapi/macro/allof"))
  end

  it "passes form: and multipart: args to union macro calls when fixture has form/multipart paths" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("form: OpenAPI::Form::Serializable")
    content.should contain("multipart: true")
  end

  it "passes form: and multipart: args to allof macro calls when fixture has form/multipart paths" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("openapi_allof AnnotatedResource, {Resource, Metadata},")
    content.should contain("form: OpenAPI::Form::Serializable")
  end

  it "does not pass format args to union when only json is active" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Petstore", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should_not contain("form: OpenAPI::Form::Serializable")
    content.should_not contain("multipart: true")
  end

  it "generates type aliases for single-ref oneOf and allOf" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("alias SingleResource = Resource")
    content.should contain("alias AliasedResource = Resource")
  end

  it "keeps mixed oneOf as JSON::Any alias" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("alias FlexPayload = JSON::Any")
  end

  it "generates valid Crystal syntax for reference fixture" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    files = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx)
    files.first.valid_syntax?.should be_true
  end
end

describe OpenAPI::Generator::TypesGenerator do
  {
    "spec/fixtures/petstore.yaml"       => "Petstore",
    "spec/fixtures/ionos-nfs-v1.yaml"   => "IonosNfs",
    "spec/fixtures/google-storage.yaml" => "GoogleStorage",
    "spec/fixtures/ionos-cloud-v6.json" => "IonosCloud",
    "spec/fixtures/stripe.json"         => "Stripe",
    "spec/fixtures/reference.yaml"      => "Reference",
  }.each do |fixture_path, namespace|
    it "generates types for #{File.basename(fixture_path)}" do
      stem = File.basename(fixture_path, File.extname(fixture_path))
      out_path = "spec/tmp/types/#{stem}.cr"
      Dir.mkdir_p("spec/tmp/types")

      doc = OpenAPI::Model::Document.from_file(fixture_path)
      ctx = OpenAPI::Generator::RenderContext.new(namespace: namespace, output_path: out_path)
      files = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx)

      files.size.should eq(1)
      File.write(files.first.path, files.first.content)
      File.exists?(out_path).should be_true
      files.first.content.should contain("module #{namespace.split("::").first}")
      files.first.content.should contain("def initialize")
      files.first.content.should contain("getter ")
      files.first.valid_syntax?.should be_true
    end
  end

  it "generates merged types for all seca fixtures" do
    out_path = "spec/tmp/types/seca.cr"
    Dir.mkdir_p("spec/tmp/types")
    docs = Dir.glob("spec/fixtures/seca/*.yaml").sort.map { |p| OpenAPI::Model::Document.from_file(p) }
    merged = OpenAPI::Model::Document.merge(docs)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Seca", output_path: out_path)
    files = OpenAPI::Generator::TypesGenerator.new.generate(merged, ctx)
    files.size.should eq(1)
    File.write(files.first.path, files.first.content)
    File.exists?(out_path).should be_true
    files.first.content.should contain("module Seca")
    files.first.valid_syntax?.should be_true
  end
end
