module OpenAPI
  module Model
    # Encoding metadata for a multipart or form field.
    class Encoding
      include YAML::Serializable
      include JSON::Serializable

      @[YAML::Field(key: "contentType")]
      @[JSON::Field(key: "contentType")]
      getter content_type : String? = nil

      getter headers : Hash(String, OrRef(Header))? = nil
      getter style : String? = nil
      getter explode : Bool? = nil

      @[YAML::Field(key: "allowReserved")]
      @[JSON::Field(key: "allowReserved")]
      getter? allow_reserved : Bool = false
    end
  end
end
