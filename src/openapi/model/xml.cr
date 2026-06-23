module OpenAPI
  module Model
    # XML serialization metadata for a schema.
    class XML
      include YAML::Serializable
      include JSON::Serializable

      getter name : String? = nil
      getter namespace : String? = nil
      getter prefix : String? = nil
      getter? attribute : Bool = false
      getter? wrapped : Bool = false
    end
  end
end
