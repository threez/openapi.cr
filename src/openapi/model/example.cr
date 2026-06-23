module OpenAPI
  module Model
    # A reusable example value.
    class Example
      include YAML::Serializable
      include JSON::Serializable

      getter summary : String? = nil
      getter description : String? = nil
      @[YAML::Field(key: "value", converter: OpenAPI::Model::AnyConverter)]
      @[JSON::Field(key: "value", converter: OpenAPI::Model::AnyConverter)]
      getter value : JSON::Any? = nil

      @[YAML::Field(key: "externalValue")]
      @[JSON::Field(key: "externalValue")]
      getter external_value : String? = nil
    end
  end
end
