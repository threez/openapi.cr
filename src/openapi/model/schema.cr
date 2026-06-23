module OpenAPI
  module Model
    # Represents either `true`/`false` or an inline/referenced Schema,
    # used for the `additionalProperties` field.
    class AdditionalProperties
      getter allowed : Bool?
      getter schema : OrRef(Schema)?

      def to_json(json : JSON::Builder) : Nil
        if allowed = @allowed
          json.bool(allowed)
        elsif schema = @schema
          schema.to_json(json)
        else
          json.null
        end
      end

      def to_json(io : IO) : Nil
        JSON.build(io) { |json| to_json(json) }
      end

      def initialize(ctx : YAML::ParseContext, node : YAML::Nodes::Node)
        if node.is_a?(YAML::Nodes::Scalar) && (node.value == "true" || node.value == "false")
          @allowed = node.value == "true"
          @schema = nil
        else
          @allowed = nil
          @schema = OrRef(Schema).new(ctx, node)
        end
      end

      def initialize(pull : JSON::PullParser)
        case pull.kind
        when .bool?
          @allowed = pull.read_bool
          @schema = nil
        else
          @allowed = nil
          @schema = OrRef(Schema).new(pull)
        end
      end
    end

    # A JSON Schema definition for a type, property, or parameter.
    class Schema
      include YAML::Serializable
      include JSON::Serializable

      # $ref — present when this schema node is a reference
      @[YAML::Field(key: "$ref")]
      @[JSON::Field(key: "$ref")]
      getter ref : String? = nil

      # Core keywords
      getter type : String? = nil
      getter format : String? = nil
      getter title : String? = nil
      getter description : String? = nil
      @[YAML::Field(key: "default", converter: OpenAPI::Model::AnyConverter)]
      @[JSON::Field(key: "default", converter: OpenAPI::Model::AnyConverter)]
      getter default : JSON::Any? = nil

      @[YAML::Field(key: "example", converter: OpenAPI::Model::AnyConverter)]
      @[JSON::Field(key: "example", converter: OpenAPI::Model::AnyConverter)]
      getter example : JSON::Any? = nil

      # Stored as JSON::Any (always an array at runtime) to unify YAML/JSON parsing.
      @[YAML::Field(key: "enum", converter: OpenAPI::Model::AnyConverter)]
      @[JSON::Field(key: "enum", converter: OpenAPI::Model::AnyConverter)]
      getter enum_values : JSON::Any? = nil

      # Numeric constraints
      @[YAML::Field(key: "minimum", converter: OpenAPI::Model::NumberConverter)]
      @[JSON::Field(key: "minimum", converter: OpenAPI::Model::NumberConverter)]
      getter minimum : Float64? = nil

      @[YAML::Field(key: "maximum", converter: OpenAPI::Model::NumberConverter)]
      @[JSON::Field(key: "maximum", converter: OpenAPI::Model::NumberConverter)]
      getter maximum : Float64? = nil

      @[YAML::Field(key: "exclusiveMinimum")]
      @[JSON::Field(key: "exclusiveMinimum")]
      getter exclusive_minimum : Bool? = nil

      @[YAML::Field(key: "exclusiveMaximum")]
      @[JSON::Field(key: "exclusiveMaximum")]
      getter exclusive_maximum : Bool? = nil

      @[YAML::Field(key: "multipleOf", converter: OpenAPI::Model::NumberConverter)]
      @[JSON::Field(key: "multipleOf", converter: OpenAPI::Model::NumberConverter)]
      getter multiple_of : Float64? = nil

      # String constraints
      @[YAML::Field(key: "minLength")]
      @[JSON::Field(key: "minLength")]
      getter min_length : Int32? = nil

      @[YAML::Field(key: "maxLength")]
      @[JSON::Field(key: "maxLength")]
      getter max_length : Int32? = nil

      getter pattern : String? = nil

      # Array constraints
      getter items : OrRef(Schema)? = nil

      @[YAML::Field(key: "minItems")]
      @[JSON::Field(key: "minItems")]
      getter min_items : Int32? = nil

      @[YAML::Field(key: "maxItems")]
      @[JSON::Field(key: "maxItems")]
      getter max_items : Int32? = nil

      @[YAML::Field(key: "uniqueItems")]
      @[JSON::Field(key: "uniqueItems")]
      getter unique_items : Bool? = nil

      # Object constraints
      getter properties : Hash(String, OrRef(Schema))? = nil

      @[YAML::Field(key: "additionalProperties", converter: OpenAPI::Model::AdditionalPropertiesConverter)]
      @[JSON::Field(key: "additionalProperties", converter: OpenAPI::Model::AdditionalPropertiesConverter)]
      getter additional_properties : AdditionalProperties? = nil

      getter required : Array(String)? = nil

      @[YAML::Field(key: "minProperties")]
      @[JSON::Field(key: "minProperties")]
      getter min_properties : Int32? = nil

      @[YAML::Field(key: "maxProperties")]
      @[JSON::Field(key: "maxProperties")]
      getter max_properties : Int32? = nil

      # Composition
      @[YAML::Field(key: "allOf")]
      @[JSON::Field(key: "allOf")]
      getter all_of : Array(OrRef(Schema))? = nil

      @[YAML::Field(key: "oneOf")]
      @[JSON::Field(key: "oneOf")]
      getter one_of : Array(OrRef(Schema))? = nil

      @[YAML::Field(key: "anyOf")]
      @[JSON::Field(key: "anyOf")]
      getter any_of : Array(OrRef(Schema))? = nil

      @[YAML::Field(key: "not")]
      @[JSON::Field(key: "not")]
      getter not_schema : OrRef(Schema)? = nil

      # Metadata
      getter? nullable : Bool = false

      @[YAML::Field(key: "readOnly")]
      @[JSON::Field(key: "readOnly")]
      getter? read_only : Bool = false

      @[YAML::Field(key: "writeOnly")]
      @[JSON::Field(key: "writeOnly")]
      getter? write_only : Bool = false

      getter? deprecated : Bool = false

      @[YAML::Field(key: "externalDocs")]
      @[JSON::Field(key: "externalDocs")]
      getter external_docs : ExternalDocumentation? = nil

      getter discriminator : Discriminator? = nil
      getter xml : XML? = nil

      @[YAML::Field(key: "x-nullable")]
      @[JSON::Field(key: "x-nullable")]
      getter? x_nullable : Bool = false

      @[YAML::Field(key: "x-additionalPropertiesName")]
      @[JSON::Field(key: "x-additionalPropertiesName")]
      getter x_additional_properties_name : String? = nil

      # Descriptions keyed by enum value string, e.g. {"active" => "Currently active"}.
      @[YAML::Field(key: "x-enumDescriptions", converter: OpenAPI::Model::AnyConverter)]
      @[JSON::Field(key: "x-enumDescriptions", converter: OpenAPI::Model::AnyConverter)]
      getter x_enum_descriptions : JSON::Any? = nil

      # Human-readable names for enum values, parallel array to `enum`.
      # x-tags — adds this schema to tag-based navigation sections.
      @[YAML::Field(key: "x-tags")]
      @[JSON::Field(key: "x-tags")]
      getter x_tags : Array(String)? = nil

      @[YAML::Field(key: "x-badges")]
      @[JSON::Field(key: "x-badges")]
      getter x_badges : Array(Badge)? = nil

      # x-rbac — hides schema/property from unauthorized users.
      @[YAML::Field(key: "x-rbac", converter: OpenAPI::Model::AnyConverter)]
      @[JSON::Field(key: "x-rbac", converter: OpenAPI::Model::AnyConverter)]
      getter x_rbac : JSON::Any? = nil

      # x-extensible-enum — like enum but allows additional runtime values beyond the listed set.
      @[YAML::Field(key: "x-extensible-enum", converter: OpenAPI::Model::AnyConverter)]
      @[JSON::Field(key: "x-extensible-enum", converter: OpenAPI::Model::AnyConverter)]
      getter x_extensible_enum : JSON::Any? = nil

      # Returns `true` when this schema node is a `$ref` pointer rather than an inline schema.
      def ref? : Bool
        !@ref.nil?
      end

      # Returns true when either the standard `nullable` flag or the Redocly
      # `x-nullable` extension is set.
      def effectively_nullable? : Bool
        nullable || x_nullable
      end
    end

    # YAML/JSON converter for `additionalProperties`, which may be a boolean or a schema/ref.
    # Used internally by `Schema`; not intended for direct use.
    module AdditionalPropertiesConverter
      def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : AdditionalProperties
        AdditionalProperties.new(ctx, node)
      end

      def self.from_json(pull : JSON::PullParser) : AdditionalProperties
        AdditionalProperties.new(pull)
      end

      def self.to_json(value : AdditionalProperties, json : JSON::Builder) : Nil
        value.to_json(json)
      end
    end
  end
end
