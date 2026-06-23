module OpenAPI
  module Model
    # An HTTP request body definition.
    class RequestBody
      include YAML::Serializable
      include JSON::Serializable

      getter description : String? = nil
      getter content : Hash(String, MediaType) = {} of String => MediaType
      getter? required : Bool = false
    end
  end
end
