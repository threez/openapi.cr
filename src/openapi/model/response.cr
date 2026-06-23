module OpenAPI
  module Model
    # An HTTP response definition.
    class Response
      include YAML::Serializable
      include JSON::Serializable

      getter description : String = ""
      getter headers : Hash(String, OrRef(Header))? = nil
      getter content : Hash(String, MediaType)? = nil
      getter links : Hash(String, OrRef(Link))? = nil

      # x-summary — short label on the response button; description appears beneath it.
      @[YAML::Field(key: "x-summary")]
      @[JSON::Field(key: "x-summary")]
      getter x_summary : String? = nil
    end
  end
end
