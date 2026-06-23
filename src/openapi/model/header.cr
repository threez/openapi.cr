module OpenAPI
  module Model
    # Like Parameter but without `name` and `in` (location is always "header").
    class Header
      include YAML::Serializable
      include JSON::Serializable

      @[YAML::Field(key: "$ref")]
      @[JSON::Field(key: "$ref")]
      getter ref : String? = nil

      getter description : String? = nil
      getter? required : Bool = false
      getter? deprecated : Bool = false

      @[YAML::Field(key: "allowEmptyValue")]
      @[JSON::Field(key: "allowEmptyValue")]
      getter? allow_empty_value : Bool = false

      getter style : String? = nil
      getter explode : Bool? = nil

      @[YAML::Field(key: "allowReserved")]
      @[JSON::Field(key: "allowReserved")]
      getter? allow_reserved : Bool = false

      getter schema : OrRef(Schema)? = nil
      @[YAML::Field(key: "example", converter: OpenAPI::Model::AnyConverter)]
      @[JSON::Field(key: "example", converter: OpenAPI::Model::AnyConverter)]
      getter example : JSON::Any? = nil
      getter examples : Hash(String, OrRef(Example))? = nil

      # Returns `true` when this header is a `$ref` pointer rather than an inline definition.
      def ref? : Bool
        !@ref.nil?
      end
    end
  end
end
