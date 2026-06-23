module OpenAPI
  module Model
    # Discriminator for polymorphic `oneOf`/`anyOf` schemas.
    class Discriminator
      include YAML::Serializable
      include JSON::Serializable

      @[YAML::Field(key: "propertyName")]
      @[JSON::Field(key: "propertyName")]
      getter property_name : String = ""

      getter mapping : Hash(String, String)? = nil

      @[YAML::Field(key: "x-explicitMappingOnly")]
      @[JSON::Field(key: "x-explicitMappingOnly")]
      getter? x_explicit_mapping_only : Bool = false
    end
  end
end
