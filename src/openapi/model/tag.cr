module OpenAPI
  module Model
    # A tag used to group operations.
    class Tag
      include YAML::Serializable
      include JSON::Serializable

      getter name : String = ""
      getter description : String? = nil

      @[YAML::Field(key: "externalDocs")]
      @[JSON::Field(key: "externalDocs")]
      getter external_docs : ExternalDocumentation? = nil

      @[YAML::Field(key: "x-displayName")]
      @[JSON::Field(key: "x-displayName")]
      getter x_display_name : String? = nil

      @[YAML::Field(key: "x-traitTag")]
      @[JSON::Field(key: "x-traitTag")]
      getter? x_trait_tag : Bool = false
    end
  end
end
