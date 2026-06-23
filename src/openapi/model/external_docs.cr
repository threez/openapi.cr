module OpenAPI
  module Model
    # A reference to external documentation.
    class ExternalDocumentation
      include YAML::Serializable
      include JSON::Serializable

      getter description : String? = nil
      getter url : String = ""
    end
  end
end
