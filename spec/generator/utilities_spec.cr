require "../spec_helper"

describe OpenAPI::Generator::Types::NameInflector do
  it "converts to snake_case" do
    i = OpenAPI::Generator::Types::NameInflector
    i.snake_case("petId").should eq("pet_id")
    i.snake_case("PetId").should eq("pet_id")
    i.snake_case("XMLParser").should eq("xml_parser")
    i.snake_case("already_fine").should eq("already_fine")
    i.snake_case("camelCase").should eq("camel_case")
  end

  it "converts to pascal_case" do
    i = OpenAPI::Generator::Types::NameInflector
    i.pascal_case("pet_id").should eq("PetId")
    i.pascal_case("camelCase").should eq("CamelCase")
    i.pascal_case("already-fine").should eq("AlreadyFine")
    i.pascal_case("PetStatus").should eq("PetStatus")
  end

  it "generates allOf part names" do
    i = OpenAPI::Generator::Types::NameInflector
    i.allof_part_name("Dog", 0).should eq("DogMerged")
    i.allof_part_name("Dog", 1).should eq("DogMerged2")
    i.allof_part_name("Dog", 2).should eq("DogMerged3")
  end

  it "makes safe identifiers" do
    i = OpenAPI::Generator::Types::NameInflector
    i.safe_identifier("in").should eq("_in")
    i.safe_identifier("type").should eq("_type")
    i.safe_identifier("normal").should eq("normal")
    i.safe_identifier("123abc").should eq("v123abc")
  end
end

describe OpenAPI::Generator::Types::TypeMapper do
  it "maps scalar types" do
    t = OpenAPI::Generator::Types::TypeMapper

    string_schema = OpenAPI::Model::Schema.from_yaml("type: string\n")
    t.crystal_type(string_schema).should eq("String")

    uuid_schema = OpenAPI::Model::Schema.from_yaml("type: string\nformat: uuid\n")
    t.crystal_type(uuid_schema).should eq("UUID")

    dt_schema = OpenAPI::Model::Schema.from_yaml("type: string\nformat: date-time\n")
    t.crystal_type(dt_schema).should eq("Time")

    int_schema = OpenAPI::Model::Schema.from_yaml("type: integer\n")
    t.crystal_type(int_schema).should eq("Int32")

    int64_schema = OpenAPI::Model::Schema.from_yaml("type: integer\nformat: int64\n")
    t.crystal_type(int64_schema).should eq("Int64")

    uint64_schema = OpenAPI::Model::Schema.from_yaml("type: integer\nformat: uint64\n")
    t.crystal_type(uint64_schema).should eq("UInt64")

    unix_time_schema = OpenAPI::Model::Schema.from_yaml("type: integer\nformat: unix-time\n")
    t.crystal_type(unix_time_schema).should eq("Int64")

    bool_schema = OpenAPI::Model::Schema.from_yaml("type: boolean\n")
    t.crystal_type(bool_schema).should eq("Bool")
  end

  it "maps array types" do
    t = OpenAPI::Generator::Types::TypeMapper
    schema = OpenAPI::Model::Schema.from_yaml("type: array\nitems:\n  type: string\n")
    t.crystal_type(schema).should eq("Array(String)")
  end

  it "identifies scalars" do
    t = OpenAPI::Generator::Types::TypeMapper
    string_schema = OpenAPI::Model::Schema.from_yaml("type: string\n")
    t.scalar?(string_schema).should be_true
    object_schema = OpenAPI::Model::Schema.from_yaml("type: object\n")
    t.scalar?(object_schema).should be_false
  end
end

describe "all-caps enum values" do
  it "preserves all-caps enum member names" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths: {}
      components:
        schemas:
          Protocol:
            type: string
            enum: [TCP, UDP, active]
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("TCP")
    content.should contain("UDP")
    content.should contain("Active")
  end

  it "omits = wire when wire equals crystal member name" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths: {}
      components:
        schemas:
          State:
            type: string
            enum: [ACTIVE, FAILED, UNKNOWN]
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("ACTIVE\n")
    content.should contain("FAILED\n")
    content.should_not contain(%( = "ACTIVE"))
    content.should_not contain(%( = "FAILED"))
  end
end

describe "x-extensible-enum" do
  it "generates a value struct with named constants" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths: {}
      components:
        schemas:
          SizeUnit:
            type: string
            x-extensible-enum:
              - TiB
              - GiB
          Protocol:
            type: string
            x-extensible-enum:
              - TCP
              - UDP
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    # mixed-case names: emitted as plain identifiers (wire == crystal name)
    content.should contain("openapi_extensible_enum SizeUnit do")
    content.should contain("    TiB\n")
    content.should contain("    GiB\n")
    content.should_not contain(%[TiB = new("TiB")])
    # all-caps names: same rule
    content.should contain("openapi_extensible_enum Protocol do")
    content.should contain("    TCP\n")
    content.should contain("    UDP\n")
  end

  it "skips unknown? when a known value already occupies that name" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths: {}
      components:
        schemas:
          LicenceType:
            type: string
            x-extensible-enum:
              - LINUX
              - UNKNOWN
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    # The macro handles known?/unknown? suppression; the generator emits the DSL call
    content.should contain("openapi_extensible_enum LicenceType do")
    content.should contain("    LINUX\n")
    content.should contain("    UNKNOWN\n")
  end

  it "emits nested extensible-enum struct and typed default for inline x-extensible-enum property" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths: {}
      components:
        schemas:
          Config:
            type: object
            properties:
              sizeUnit:
                type: string
                default: TiB
                x-extensible-enum:
                  - TiB
                  - GiB
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    # inline x-extensible-enum → macro call + typed constant default
    content.should contain("openapi_extensible_enum SizeUnit do")
    content.should contain("getter size_unit : SizeUnit = SizeUnit::TiB")
    content.should_not contain("getter size_unit : String")
  end
end

describe "format selection" do
  it "omits yaml automatically when spec has no yaml content types" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths:
        /pets:
          get:
            operationId: listPets
            responses:
              "200":
                description: ok
                content:
                  application/json:
                    schema:
                      type: object
      components:
        schemas:
          Pet:
            type: object
            required: [name]
            properties:
              name:
                type: string
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("require \"json\"")
    content.should contain("include JSON::Serializable")
    content.should_not contain("require \"yaml\"")
    content.should_not contain("include YAML::Serializable")
  end

  it "emits only json when yaml is excluded" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths: {}
      components:
        schemas:
          Pet:
            type: object
            required: [name]
            properties:
              name:
                type: string
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null", formats: Set{"json"})
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("require \"json\"")
    content.should contain("include JSON::Serializable")
    content.should_not contain("require \"yaml\"")
    content.should_not contain("include YAML::Serializable")
  end

  it "emits no serialization when formats is empty" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths: {}
      components:
        schemas:
          Pet:
            type: object
            required: [name]
            properties:
              name:
                type: string
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null", formats: Set(String).new)
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should_not contain("require \"json\"")
    content.should_not contain("require \"yaml\"")
    content.should_not contain("include JSON::Serializable")
    content.should_not contain("include YAML::Serializable")
  end
end

describe "default values" do
  it "emits scalar defaults instead of nil" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths: {}
      components:
        schemas:
          Config:
            type: object
            properties:
              pageSize:
                type: integer
                default: 20
              enabled:
                type: boolean
                default: false
              status:
                type: string
                default: "active"
              tag:
                type: string
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("getter page_size : Int32 = 20")
    content.should contain("getter enabled : Bool = false")
    content.should contain(%[getter status : String = "active"])
    content.should contain("getter tag : String? = nil")
  end
end

describe "x-enumDescriptions" do
  it "emits member comments from x-enumDescriptions" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths: {}
      components:
        schemas:
          Status:
            type: string
            enum: [active, inactive, pending]
            x-enumDescriptions:
              active: "Account is live."
              inactive: "Account has been deactivated."
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("# Account is live.")
    content.should contain("Active")
    content.should contain("# Account has been deactivated.")
    content.should contain("Inactive")
  end

  it "emits member comments from x-enumDescriptions for extensible enums" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths: {}
      components:
        schemas:
          Protocol:
            type: string
            x-extensible-enum:
              - TCP
              - UDP
            x-enumDescriptions:
              TCP: "Transmission Control Protocol."
              UDP: "User Datagram Protocol."
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("# Transmission Control Protocol.")
    content.should contain("TCP\n")
    content.should contain("# User Datagram Protocol.")
    content.should contain("UDP\n")
  end
end

describe "x-additionalPropertiesName" do
  it "generates Hash type with key comment" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths: {}
      components:
        schemas:
          Labels:
            type: object
            additionalProperties:
              type: string
              x-additionalPropertiesName: labelKey
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("Hash(String, String)")
    content.should contain("# Keys: labelKey")
  end
end
