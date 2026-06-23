require "uri"

module OpenAPI
  module Model
    # The parsed representation of an OpenAPI 3.x spec.
    # Load from a file or string with `from_file` / `from_string`, or combine
    # multiple specs with `merge`.
    class Document
      include YAML::Serializable
      include JSON::Serializable

      getter openapi : String = ""
      getter info : Info
      getter servers : Array(Server)? = nil
      getter paths : Hash(String, PathItem)? = nil
      getter components : Components? = nil
      getter security : Array(SecurityRequirement)? = nil
      getter tags : Array(Tag)? = nil

      @[YAML::Field(key: "externalDocs")]
      @[JSON::Field(key: "externalDocs")]
      getter external_docs : ExternalDocumentation? = nil

      @[YAML::Field(key: "x-tagGroups")]
      @[JSON::Field(key: "x-tagGroups")]
      getter x_tag_groups : Array(TagGroup)? = nil

      # x-webhooks — same structure as paths; webhook definitions.
      @[YAML::Field(key: "x-webhooks")]
      @[JSON::Field(key: "x-webhooks")]
      getter x_webhooks : Hash(String, PathItem)? = nil

      @[YAML::Field(key: "x-ignoredHeaderParameters")]
      @[JSON::Field(key: "x-ignoredHeaderParameters")]
      getter x_ignored_header_parameters : Array(String)? = nil

      # x-mcp — MCP server/tool definitions. Kept as JSON::Any due to schema complexity.
      @[YAML::Field(key: "x-mcp", converter: OpenAPI::Model::AnyConverter)]
      @[JSON::Field(key: "x-mcp", converter: OpenAPI::Model::AnyConverter)]
      getter x_mcp : JSON::Any? = nil

      # :nodoc:
      def initialize(
        @info : Info,
        @openapi : String = "3.0.3",
        @paths : Hash(String, PathItem)? = nil,
        @components : Components? = nil,
        @servers : Array(Server)? = nil,
        @tags : Array(Tag)? = nil,
        @security : Array(SecurityRequirement)? = nil,
        @external_docs : ExternalDocumentation? = nil,
        @x_tag_groups : Array(TagGroup)? = nil,
        @x_webhooks : Hash(String, PathItem)? = nil,
        @x_ignored_header_parameters : Array(String)? = nil,
        @x_mcp : JSON::Any? = nil,
      )
      end

      # Merges multiple documents into one unified document.
      # Each spec's server URL path component is prepended to its paths so that
      # overlapping routes (e.g. `/v1/skus` in two specs) become distinct.
      # Component schemas use first-write-wins; servers and tags are deduplicated.
      def self.merge(docs : Array(Document)) : Document
        raise ArgumentError.new("docs must not be empty") if docs.empty?
        first = docs.first

        merged_paths = {} of String => PathItem
        merged_servers = [] of Server
        merged_tags = [] of Tag

        docs.each do |doc|
          base_path = server_base_path(doc.servers)
          doc.paths.try do |paths|
            paths.each do |path_key, path_item|
              full_key = base_path.empty? ? path_key : "#{base_path}#{path_key}"
              merged_paths[full_key] = path_item unless merged_paths.has_key?(full_key)
            end
          end
          doc.servers.try do |servers|
            servers.each do |sv|
              base_url = server_base_url(sv.url)
              merged_servers << Server.new(base_url) unless merged_servers.any? { |e| e.url == base_url }
            end
          end
          doc.tags.try { |t| t.each { |tag| merged_tags << tag unless merged_tags.any? { |e| e.name == tag.name } } }
        end

        new(
          info: first.info,
          openapi: first.openapi,
          paths: merged_paths.empty? ? nil : merged_paths,
          components: Components.merge(docs.compact_map(&.components)),
          servers: merged_servers.empty? ? nil : merged_servers,
          tags: merged_tags.empty? ? nil : merged_tags,
          security: first.security,
          external_docs: first.external_docs,
          x_tag_groups: first.x_tag_groups,
          x_webhooks: first.x_webhooks,
          x_ignored_header_parameters: first.x_ignored_header_parameters,
          x_mcp: first.x_mcp,
        )
      end

      private def self.server_base_path(servers : Array(Server)?) : String
        return "" if servers.nil? || servers.empty?
        uri = URI.parse(servers.first.url)
        path = uri.path || ""
        path == "/" ? "" : path
      end

      private def self.server_base_url(url : String) : String
        uri = URI.parse(url)
        port = uri.port
        port ? "#{uri.scheme}://#{uri.host}:#{port}" : "#{uri.scheme}://#{uri.host}"
      end

      # Loads an OpenAPI spec from *path*, auto-detecting JSON or YAML by content.
      def self.from_file(path : String) : self
        content = File.read(path)
        from_string(content)
      end

      # Parses an OpenAPI spec from a string, auto-detecting JSON or YAML by content.
      def self.from_string(content : String) : self
        content.lstrip[0]? == '{' ? from_json(content) : from_yaml(content)
      end

      # The major version of the OpenAPI specification (2 or 3).
      def openapi_major_version : Int32
        openapi.split(".").first.to_i
      end

      # Yields each path template and its resolved PathItem.
      # Entries whose `$ref` cannot be resolved are silently skipped.
      def each_path_item(& : String, PathItem ->)
        paths.try(&.each do |template, item|
          resolved = resolve_path_item(item) || next
          yield template, resolved
        end)
      end

      private def resolve_path_item(item : PathItem) : PathItem?
        ref = item.ref || return item
        # External file refs are not supported (path-traversal / SSRF risk).
        return nil unless ref.starts_with?("#/paths/")
        # Decode RFC 6901 JSON Pointer escapes: ~1 → /, ~0 → ~
        key = ref[8..].gsub("~1", "/").gsub("~0", "~")
        paths.try(&.[key]?)
      end
    end
  end
end
