module OpenAPI
  module Model
    # A substitution variable used in a server URL template.
    class ServerVariable
      include YAML::Serializable
      include JSON::Serializable

      @[YAML::Field(key: "enum")]
      @[JSON::Field(key: "enum")]
      getter enum_values : Array(String)? = nil

      getter default : String = ""
      getter description : String? = nil
    end

    # An API server entry from the `servers` array.
    class Server
      include YAML::Serializable
      include JSON::Serializable

      getter url : String = ""
      getter description : String? = nil
      getter variables : Hash(String, ServerVariable)? = nil

      # :nodoc:
      def initialize(@url : String, @description : String? = nil, @variables : Hash(String, ServerVariable)? = nil)
      end
    end
  end
end
