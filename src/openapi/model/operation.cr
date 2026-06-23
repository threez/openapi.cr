module OpenAPI
  module Model
    # Security requirement: map of scheme name to required scopes.
    alias SecurityRequirement = Hash(String, Array(String))

    # An HTTP operation (GET, POST, etc.) on a path.
    class Operation
      include YAML::Serializable
      include JSON::Serializable

      getter tags : Array(String)? = nil
      getter summary : String? = nil
      getter description : String? = nil

      @[YAML::Field(key: "externalDocs")]
      @[JSON::Field(key: "externalDocs")]
      getter external_docs : ExternalDocumentation? = nil

      @[YAML::Field(key: "operationId")]
      @[JSON::Field(key: "operationId")]
      getter operation_id : String? = nil

      getter parameters : Array(OrRef(Parameter))? = nil

      @[YAML::Field(key: "requestBody")]
      @[JSON::Field(key: "requestBody")]
      getter request_body : OrRef(RequestBody)? = nil

      getter responses : Hash(String, OrRef(Response)) = {} of String => OrRef(Response)

      # Callback map: name → {expression → PathItem}
      # PathItem is a forward-declared class; fully defined in path_item.cr.
      getter callbacks : Hash(String, Hash(String, PathItem))? = nil

      getter? deprecated : Bool = false
      getter security : Array(SecurityRequirement)? = nil
      getter servers : Array(Server)? = nil

      # x-codeSamples — language-specific code examples shown in the docs panel.
      # Both spellings are supported; x-codeSamples takes precedence.
      @[YAML::Field(key: "x-codeSamples")]
      @[JSON::Field(key: "x-codeSamples")]
      getter x_code_samples : Array(CodeSample)? = nil

      @[YAML::Field(key: "x-code-samples")]
      @[JSON::Field(key: "x-code-samples")]
      getter x_code_samples_kebab : Array(CodeSample)? = nil

      # x-hideReplay — hides the interactive "Try It" button for this operation.
      @[YAML::Field(key: "x-hideReplay")]
      @[JSON::Field(key: "x-hideReplay")]
      getter? x_hide_replay : Bool = false

      @[YAML::Field(key: "x-badges")]
      @[JSON::Field(key: "x-badges")]
      getter x_badges : Array(Badge)? = nil

      # x-rbac — maps team names to roles; hides operation from non-authorized users.
      @[YAML::Field(key: "x-rbac", converter: OpenAPI::Model::AnyConverter)]
      @[JSON::Field(key: "x-rbac", converter: OpenAPI::Model::AnyConverter)]
      getter x_rbac : JSON::Any? = nil

      def code_samples : Array(CodeSample)
        x_code_samples || x_code_samples_kebab || [] of CodeSample
      end
    end
  end
end
