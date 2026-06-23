module OpenAPI
  module Model
    # A media type entry inside a response or request body.
    class MediaType
      include YAML::Serializable
      include JSON::Serializable

      getter schema : OrRef(Schema)? = nil
      @[YAML::Field(key: "example", converter: OpenAPI::Model::AnyConverter)]
      @[JSON::Field(key: "example", converter: OpenAPI::Model::AnyConverter)]
      getter example : JSON::Any? = nil
      getter examples : Hash(String, OrRef(Example))? = nil
      getter encoding : Hash(String, Encoding)? = nil
    end
  end
end
