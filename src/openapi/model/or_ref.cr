module OpenAPI
  module Model
    # Wraps a field that may be either an inline object or a `$ref` pointer.
    # Call `value` to get the resolved object, or `ref` to get the reference string.
    struct OrRef(T)
      getter ref : String?
      getter value : T?

      def initialize(@ref : String)
        @value = nil
      end

      def initialize(@value : T)
        @ref = nil
      end

      # :nodoc:
      def initialize(ctx : YAML::ParseContext, node : YAML::Nodes::Node)
        if node.is_a?(YAML::Nodes::Mapping)
          i = 0
          nodes = node.nodes
          while i < nodes.size - 1
            key = nodes[i]
            val = nodes[i + 1]
            if key.is_a?(YAML::Nodes::Scalar) && key.value == "$ref"
              unless val.is_a?(YAML::Nodes::Scalar)
                node.raise "Expected a scalar value for $ref"
              end
              @ref = val.value
              @value = nil
              return
            end
            i += 2
          end
        end
        @ref = nil
        @value = T.new(ctx, node)
      end

      # :nodoc:
      def initialize(pull : JSON::PullParser)
        raw = JSON::Any.new(pull)
        if ref_val = raw.as_h?.try { |h| h["$ref"]? }
          @ref = ref_val.as_s
          @value = nil
        else
          @ref = nil
          @value = T.from_json(raw.to_json)
        end
      end

      # Returns `true` when this entry holds a `$ref` string rather than an inline value.
      def ref? : Bool
        !@ref.nil?
      end

      # Returns the inline value.
      # Raises `NilAssertionError` when called on a `$ref`-only instance — check `ref?` first.
      def resolved : T
        @value.not_nil! # ameba:disable Lint/NotNil
      end

      def to_json(json : JSON::Builder) : Nil
        if ref = @ref
          json.object { json.field "$ref", ref }
        elsif value = @value
          value.to_json(json)
        else
          json.null
        end
      end

      def to_json(io : IO) : Nil
        JSON.build(io) { |json| to_json(json) }
      end
    end
  end
end
