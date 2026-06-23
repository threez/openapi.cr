require "../spec_helper"

private class DecimalHooks < OpenAPI::Generator::Types::DefaultHooks
  def format_type_for(openapi_type : String, format : String?) : String?
    "BigDecimal" if openapi_type == "number" && format == "decimal"
  end
end

describe "validation methods" do
  it "emits valid? and validate! for constrained properties" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths: {}
      components:
        schemas:
          NfsShare:
            type: object
            required: [gid, uid]
            properties:
              gid:
                type: integer
                minimum: 0
                maximum: 65534
              uid:
                type: integer
                minimum: 0
                maximum: 65534
              name:
                type: string
                minLength: 1
                maxLength: 255
                pattern: "^[a-zA-Z0-9_-]+$"
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("include OpenAPI::Validation::Helpers")
    content.should contain("def valid? : Array(OpenAPI::Validation::Error)")
    content.should contain("def validate! : Nil")
    content.should contain("raise OpenAPI::Validation::Exception.new(errors)")
    content.should contain(%(validate_minimum errors, "gid", @gid, 0))
    content.should contain(%(validate_maximum errors, "gid", @gid, 65534))
    content.should contain(%(validate_min_length errors, "name", @name, 1))
    content.should contain(%(validate_max_length errors, "name", @name, 255))
    content.should contain(%(validate_pattern errors, "name", @name, /^[a-zA-Z0-9_-]+$/, "^[a-zA-Z0-9_-]+$"))
  end

  it "emits regex patterns with backslash metacharacters correctly" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths: {}
      components:
        schemas:
          Item:
            type: object
            properties:
              code:
                type: string
                pattern: "^\\\\d{3}-\\\\d{4}$"
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    # The emitted regex literal must contain the backslash metacharacters verbatim, not doubled
    content.should contain("validate_pattern errors, \"code\", @code, /^\\d{3}-\\d{4}$/")
  end

  it "does not emit valid? when no constraints exist" do
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
            properties:
              name:
                type: string
              age:
                type: integer
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should_not contain("def valid?")
    content.should_not contain("def validate!")
  end

  it "does not emit valid? for an inline enum property (type system enforces)" do
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
              mode:
                type: string
                enum: [read, write, admin]
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("openapi_enum Mode do")
    content.should contain(%("read"))
    content.should_not contain("def valid?")
    content.should_not contain("includes?")
    content.should_not contain(%(require "openapi/validation/error"))
  end

  it "emits yaml format arg on openapi_enum when doc has YAML content type" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths:
        /config:
          get:
            responses:
              "200":
                content:
                  application/yaml:
                    schema:
                      $ref: "#/components/schemas/Config"
      components:
        schemas:
          Config:
            type: object
            properties:
              mode:
                type: string
                enum: [read, write]
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("openapi_enum Mode, yaml: true do")
  end

  it "adds require for validation/error in header when constraints exist" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths: {}
      components:
        schemas:
          Item:
            type: object
            properties:
              count:
                type: integer
                minimum: 1
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain(%(require "openapi/validation/error"))
  end

  it "omits validation require when no constraints exist" do
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
            properties:
              name:
                type: string
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should_not contain("openapi/validation/error")
  end
end

describe "inline object properties" do
  it "emits a nested class for an inline object property" do
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
            properties:
              address:
                type: object
                properties:
                  street:
                    type: string
                  city:
                    type: string
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("class Address")
    content.should contain("getter street : String?")
    content.should contain("getter city : String?")
    content.should contain("getter address : Address?")
    content.should_not contain("getter address : JSON::Any")
  end

  it "emits a nested class for an inline array-of-objects property" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths: {}
      components:
        schemas:
          Group:
            type: object
            properties:
              members:
                type: array
                items:
                  type: object
                  properties:
                    name:
                      type: string
                    role:
                      type: string
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("class Members")
    content.should contain("getter name : String?")
    content.should contain("getter role : String?")
    content.should contain("getter members : Array(Members)?")
    content.should_not contain("getter members : Array(JSON::Any)")
  end

  it "emits nested classes recursively for deeply nested inline objects" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths: {}
      components:
        schemas:
          Order:
            type: object
            properties:
              customer:
                type: object
                properties:
                  contact:
                    type: object
                    properties:
                      email:
                        type: string
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("class Customer")
    content.should contain("class Contact")
    content.should contain("getter email : String?")
    content.should contain("getter contact : Contact?")
    content.should contain("getter customer : Customer?")
  end

  it "does not emit a nested class for a ref property" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths: {}
      components:
        schemas:
          Address:
            type: object
            properties:
              street:
                type: string
          Pet:
            type: object
            properties:
              address:
                $ref: "#/components/schemas/Address"
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("getter address : Address?")
    # Only one class Address (the top-level one), not a second nested definition
    content.scan("class Address").size.should eq(1)
  end

  it "emits a nested enum for an inline enum property" do
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
            properties:
              status:
                type: string
                enum: [active, inactive, pending]
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("enum Status")
    content.should contain("Active")
    content.should contain("Inactive")
    content.should contain("Pending")
    content.should contain("getter status : Status?")
    content.should_not contain("getter status : String")
  end

  it "emits a nested extensible-enum struct for an inline x-extensible-enum property" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths: {}
      components:
        schemas:
          Storage:
            type: object
            properties:
              sizeUnit:
                type: string
                x-extensible-enum:
                  - TiB
                  - GiB
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("openapi_extensible_enum SizeUnit do")
    content.should_not contain(%[TiB = new("TiB")])
    content.should contain("getter size_unit : SizeUnit?")
    content.should_not contain("getter size_unit : String")
  end

  it "does not emit a nested class for a scalar property" do
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
            properties:
              name:
                type: string
              age:
                type: integer
      YAML
    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("getter name : String?")
    content.should contain("getter age : Int32?")
    content.should_not contain("class Name")
    content.should_not contain("class Age")
  end
end

describe "custom format mappings via Hooks" do
  it "uses format_type_for hook to override property types" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths: {}
      components:
        schemas:
          Invoice:
            type: object
            properties:
              amount:
                type: number
                format: decimal
              tag:
                type: string
      YAML

    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new(DecimalHooks.new).generate(doc, ctx).first.content
    content.should contain("getter amount : BigDecimal?")
    content.should contain("getter tag : String?")
  end

  it "uses format_type_for hook to override top-level scalar alias types" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths: {}
      components:
        schemas:
          Amount:
            type: number
            format: decimal
      YAML

    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new(DecimalHooks.new).generate(doc, ctx).first.content
    content.should contain("alias Amount = BigDecimal")
  end
end

describe "exception subclass initialize" do
  it "emits openapi_exception macro call for error classes" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths:
        /items:
          get:
            operationId: listItems
            responses:
              '200':
                description: ok
                content:
                  application/json:
                    schema:
                      type: string
              default:
                description: error
                content:
                  application/json:
                    schema:
                      $ref: '#/components/schemas/ApiError'
      components:
        schemas:
          ApiError:
            type: object
            required: [code, message]
            properties:
              code:
                type: integer
                format: int32
              message:
                type: string
      YAML

    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("require \"openapi/macro/exception\"")
    content.should contain("openapi_exception ApiError do")
    content.should contain("getter code : Int32")
    content.should contain("getter message : String")
    content.should_not contain("class ApiError < Exception")
    content.should_not contain("struct Body")
  end

  it "emits openapi_exception macro call without message property" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths:
        /items:
          get:
            operationId: listItems
            responses:
              '200':
                description: ok
                content:
                  application/json:
                    schema:
                      type: string
              default:
                description: error
                content:
                  application/json:
                    schema:
                      $ref: '#/components/schemas/ApiError'
      components:
        schemas:
          ApiError:
            type: object
            required: [code]
            properties:
              code:
                type: integer
                format: int32
      YAML

    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("openapi_exception ApiError do")
    content.should contain("getter code : Int32")
    content.should_not contain("class ApiError < Exception")
  end

  it "emits openapi_exception with yaml: true for YAML-only error docs" do
    yaml = <<-YAML
      openapi: "3.0.0"
      info:
        title: Test
        version: "1"
      paths:
        /items:
          get:
            operationId: listItems
            responses:
              '200':
                description: ok
                content:
                  application/yaml:
                    schema:
                      type: string
              default:
                description: error
                content:
                  application/yaml:
                    schema:
                      $ref: '#/components/schemas/ApiError'
      components:
        schemas:
          ApiError:
            type: object
            required: [code, message]
            properties:
              code:
                type: integer
                format: int32
              message:
                type: string
      YAML

    doc = OpenAPI::Model::Document.from_string(yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("openapi_exception ApiError, yaml: true do")
    content.should_not contain("struct Body")
  end
end

describe "--form-serializer option" do
  form_spec_yaml = <<-YAML
    openapi: "3.0.0"
    info:
      title: Test
      version: "1"
    paths:
      /items:
        post:
          operationId: createItem
          requestBody:
            content:
              application/x-www-form-urlencoded:
                schema:
                  $ref: '#/components/schemas/NewItem'
          responses:
            "201":
              description: created
    components:
      schemas:
        NewItem:
          type: object
          required: [name]
          properties:
            name:
              type: string
    YAML

  it "defaults to OpenAPI::Form::Serializable" do
    doc = OpenAPI::Model::Document.from_string(form_spec_yaml)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "T", output_path: "/dev/null")
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("include OpenAPI::Form::Serializable")
    content.should contain(%(require "openapi/form/serializable"))
  end

  it "substitutes a custom serializer module and omits the built-in require" do
    doc = OpenAPI::Model::Document.from_string(form_spec_yaml)
    ctx = OpenAPI::Generator::RenderContext.new(
      namespace: "T",
      output_path: "/dev/null",
      form_serializer: "MyApp::FormEncoder"
    )
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    content.should contain("include MyApp::FormEncoder")
    content.should_not contain("include OpenAPI::Form::Serializable")
    content.should_not contain(%(require "openapi/form/serializable"))
  end
end
