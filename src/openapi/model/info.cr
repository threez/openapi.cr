module OpenAPI
  module Model
    # Contact information for the API maintainer.
    class Contact
      include YAML::Serializable
      include JSON::Serializable

      getter name : String? = nil
      getter url : String? = nil
      getter email : String? = nil
    end

    # License information for the API.
    class License
      include YAML::Serializable
      include JSON::Serializable

      getter name : String = ""
      getter url : String? = nil
    end

    # Metadata for the API (title, version, description).
    class Info
      include YAML::Serializable
      include JSON::Serializable

      getter title : String = ""
      getter description : String? = nil

      @[YAML::Field(key: "termsOfService")]
      @[JSON::Field(key: "termsOfService")]
      getter terms_of_service : String? = nil

      getter contact : Contact? = nil
      getter license : License? = nil
      getter version : String = ""

      @[YAML::Field(key: "x-logo")]
      @[JSON::Field(key: "x-logo")]
      getter x_logo : Logo? = nil

      @[YAML::Field(key: "x-metadata", converter: OpenAPI::Model::AnyConverter)]
      @[JSON::Field(key: "x-metadata", converter: OpenAPI::Model::AnyConverter)]
      getter x_metadata : JSON::Any? = nil
    end
  end
end
