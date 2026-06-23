module OpenAPI
  module Model
    # A hypermedia link between operations.
    class Link
      include YAML::Serializable
      include JSON::Serializable

      @[YAML::Field(key: "operationRef")]
      @[JSON::Field(key: "operationRef")]
      getter operation_ref : String? = nil

      @[YAML::Field(key: "operationId")]
      @[JSON::Field(key: "operationId")]
      getter operation_id : String? = nil

      @[YAML::Field(key: "parameters", converter: OpenAPI::Model::AnyConverter)]
      @[JSON::Field(key: "parameters", converter: OpenAPI::Model::AnyConverter)]
      getter parameters : JSON::Any? = nil

      @[YAML::Field(key: "requestBody", converter: OpenAPI::Model::AnyConverter)]
      @[JSON::Field(key: "requestBody", converter: OpenAPI::Model::AnyConverter)]
      getter request_body : JSON::Any? = nil

      getter description : String? = nil
      getter server : Server? = nil
    end
  end
end
