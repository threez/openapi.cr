module OpenAPI
  module Model
    # Reusable component definitions shared across the API (schemas, responses,
    # parameters, headers, request bodies, security schemes, links, callbacks).
    class Components
      include YAML::Serializable
      include JSON::Serializable

      getter schemas : Hash(String, OrRef(Schema))? = nil
      getter responses : Hash(String, OrRef(Response))? = nil
      getter parameters : Hash(String, OrRef(Parameter))? = nil
      getter examples : Hash(String, OrRef(Example))? = nil

      @[YAML::Field(key: "requestBodies")]
      @[JSON::Field(key: "requestBodies")]
      getter request_bodies : Hash(String, OrRef(RequestBody))? = nil

      getter headers : Hash(String, OrRef(Header))? = nil

      @[YAML::Field(key: "securitySchemes")]
      @[JSON::Field(key: "securitySchemes")]
      getter security_schemes : Hash(String, OrRef(SecurityScheme))? = nil

      getter links : Hash(String, OrRef(Link))? = nil
      getter callbacks : Hash(String, Hash(String, PathItem))? = nil

      # :nodoc:
      def initialize(
        @schemas : Hash(String, OrRef(Schema))? = nil,
        @responses : Hash(String, OrRef(Response))? = nil,
        @parameters : Hash(String, OrRef(Parameter))? = nil,
        @examples : Hash(String, OrRef(Example))? = nil,
        @request_bodies : Hash(String, OrRef(RequestBody))? = nil,
        @headers : Hash(String, OrRef(Header))? = nil,
        @security_schemes : Hash(String, OrRef(SecurityScheme))? = nil,
        @links : Hash(String, OrRef(Link))? = nil,
        @callbacks : Hash(String, Hash(String, PathItem))? = nil,
      )
      end

      # :nodoc:
      def self.merge(comps : Array(Components)) : Components?
        return nil if comps.empty?
        new(
          schemas: merge_hashes(comps.compact_map(&.schemas)),
          responses: merge_hashes(comps.compact_map(&.responses)),
          parameters: merge_hashes(comps.compact_map(&.parameters)),
          examples: merge_hashes(comps.compact_map(&.examples)),
          request_bodies: merge_hashes(comps.compact_map(&.request_bodies)),
          headers: merge_hashes(comps.compact_map(&.headers)),
          security_schemes: merge_hashes(comps.compact_map(&.security_schemes)),
          links: merge_hashes(comps.compact_map(&.links)),
          callbacks: merge_hashes(comps.compact_map(&.callbacks)),
        )
      end

      private def self.merge_hashes(hashes : Array(Hash(String, V))) : Hash(String, V)? forall V
        return nil if hashes.empty?
        result = {} of String => V
        hashes.each { |h| h.each { |k, v| result[k] = v unless result.has_key?(k) } }
        result.empty? ? nil : result
      end
    end
  end
end
