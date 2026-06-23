module OpenAPI
  module Model
    # A path, query, header, or cookie parameter.
    class Parameter
      include YAML::Serializable
      include JSON::Serializable

      getter name : String = ""

      # Stored as `location` because `in` is a reserved word in Crystal.
      @[YAML::Field(key: "in")]
      @[JSON::Field(key: "in")]
      getter location : String = ""

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
      getter content : Hash(String, MediaType)? = nil
    end
  end
end
