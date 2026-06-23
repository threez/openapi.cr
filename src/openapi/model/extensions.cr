module OpenAPI
  module Model
    # x-logo on Info — branding for API documentation portals.
    class Logo
      include YAML::Serializable
      include JSON::Serializable

      getter url : String = ""

      @[YAML::Field(key: "altText")]
      @[JSON::Field(key: "altText")]
      getter alt_text : String? = nil

      getter href : String? = nil

      @[YAML::Field(key: "backgroundColor")]
      @[JSON::Field(key: "backgroundColor")]
      getter background_color : String? = nil
    end

    # x-tagGroups on Document — groups tags in sidebar navigation.
    class TagGroup
      include YAML::Serializable
      include JSON::Serializable

      getter name : String = ""
      getter tags : Array(String) = [] of String
    end

    # One entry in x-codeSamples on Operation.
    class CodeSample
      include YAML::Serializable
      include JSON::Serializable

      getter lang : String = ""
      getter label : String? = nil
      getter source : String = ""
    end

    # One entry in x-badges on Operation or Schema property.
    class Badge
      include YAML::Serializable
      include JSON::Serializable

      getter name : String = ""
      getter color : String = "grey"

      # "before" | "after" — position relative to the operation/property name.
      getter position : String = "after"
    end
  end
end
