module OpenAPI
  module Model
    # Configuration for a single OAuth 2.0 flow (implicit, password,
    # clientCredentials, or authorizationCode).
    class OAuthFlow
      include YAML::Serializable
      include JSON::Serializable

      @[YAML::Field(key: "authorizationUrl")]
      @[JSON::Field(key: "authorizationUrl")]
      getter authorization_url : String? = nil

      @[YAML::Field(key: "tokenUrl")]
      @[JSON::Field(key: "tokenUrl")]
      getter token_url : String? = nil

      @[YAML::Field(key: "refreshUrl")]
      @[JSON::Field(key: "refreshUrl")]
      getter refresh_url : String? = nil

      getter scopes : Hash(String, String) = {} of String => String

      # x-usePkce — enables PKCE on authorizationCode flow.
      @[YAML::Field(key: "x-usePkce")]
      @[JSON::Field(key: "x-usePkce")]
      getter? x_use_pkce : Bool = false

      # x-assertionType — JWT assertion type for clientCredentials flow.
      @[YAML::Field(key: "x-assertionType")]
      @[JSON::Field(key: "x-assertionType")]
      getter x_assertion_type : String? = nil
    end

    # Container for all supported OAuth 2.0 flow configurations.
    class OAuthFlows
      include YAML::Serializable
      include JSON::Serializable

      getter implicit : OAuthFlow? = nil
      getter password : OAuthFlow? = nil

      @[YAML::Field(key: "clientCredentials")]
      @[JSON::Field(key: "clientCredentials")]
      getter client_credentials : OAuthFlow? = nil

      @[YAML::Field(key: "authorizationCode")]
      @[JSON::Field(key: "authorizationCode")]
      getter authorization_code : OAuthFlow? = nil
    end

    # An authentication/authorization scheme definition.
    class SecurityScheme
      include YAML::Serializable
      include JSON::Serializable

      getter type : String = ""
      getter description : String? = nil

      # For `apiKey`
      getter name : String? = nil

      @[YAML::Field(key: "in")]
      @[JSON::Field(key: "in")]
      getter location : String? = nil

      # For `http`
      getter scheme : String? = nil

      @[YAML::Field(key: "bearerFormat")]
      @[JSON::Field(key: "bearerFormat")]
      getter bearer_format : String? = nil

      # For `oauth2`
      getter flows : OAuthFlows? = nil

      # For `openIdConnect`
      @[YAML::Field(key: "openIdConnectUrl")]
      @[JSON::Field(key: "openIdConnectUrl")]
      getter open_id_connect_url : String? = nil
    end
  end
end
