module OpenAPI
  module Model
    # :nodoc:
    module AnyConverter
      def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : JSON::Any
        yaml_to_json(YAML::Any.new(ctx, node))
      end

      def self.from_json(pull : JSON::PullParser) : JSON::Any
        JSON::Any.new(pull)
      end

      def self.to_json(value : JSON::Any, json : JSON::Builder) : Nil
        json.raw(value.to_json)
      end

      private def self.yaml_to_json(ya : YAML::Any) : JSON::Any
        case raw = ya.raw
        when String
          JSON::Any.new(raw)
        when Int64
          JSON::Any.new(raw)
        when Float64
          JSON::Any.new(raw)
        when Bool
          JSON::Any.new(raw)
        when Nil
          JSON::Any.new(nil)
        when Array(YAML::Any)
          JSON::Any.new(raw.map { |v| yaml_to_json(v) })
        when Hash(YAML::Any, YAML::Any)
          h = {} of String => JSON::Any
          raw.each { |k, v| h[k.as_s] = yaml_to_json(v) }
          JSON::Any.new(h)
        else
          JSON::Any.new(ya.to_s)
        end
      end
    end
  end
end
