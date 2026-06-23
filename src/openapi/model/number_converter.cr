module OpenAPI
  module Model
    # :nodoc:
    module NumberConverter
      def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Float64
        ya = YAML::Any.new(ctx, node)
        case raw = ya.raw
        when Int64   then raw.to_f
        when Float64 then raw
        else
          node.raise "Expected a number for schema constraint, got #{raw.class}"
        end
      end

      def self.from_json(pull : JSON::PullParser) : Float64
        case pull.kind
        when .int?   then pull.read_int.to_f64
        when .float? then pull.read_float
        else
          raise JSON::ParseException.new("Expected a number", *pull.location)
        end
      end

      def self.to_json(value : Float64, json : JSON::Builder) : Nil
        if value == value.to_i64.to_f64
          json.number(value.to_i64)
        else
          json.number(value)
        end
      end
    end
  end
end
