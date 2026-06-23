module OpenAPI
  module Generator
    # Shared helpers for header/cookie parameter handling and response-header
    # type generation.  Included by both `ClientGenerator` and `ServerGenerator`.
    module ParamHelpers
      private alias NameInflector = Types::NameInflector
      private alias TypeMapper = Types::TypeMapper

      # Builds the Crystal named-tuple type string for a group of parameters.
      # Required params use a non-nilable type; optional params get `?`.
      # e.g. `"{x_api_key: String, x_contract_number: Int32?}"`
      private def named_tuple_type(params : Array(Model::Parameter)) : String
        fields = params.map do |p|
          crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
          base = resolve_type(p.schema, p.name).rchop('?')
          type = p.required? ? base : "#{base}?"
          "#{crystal_name}: #{type}"
        end
        "{ #{fields.join(", ")} }"
      end

      # Returns the named-tuple type string for the declared response headers of the
      # first 2xx response, or nil when none are declared.
      private def resolve_response_headers_type(operation : Model::Operation) : String?
        resp_or_ref =
          operation.responses["200"]? ||
            operation.responses["201"]? ||
            operation.responses.find { |k, _| k.starts_with?("2") }.try(&.last)
        response = resp_or_ref.try(&.value) || return nil
        headers = response.headers || return nil
        return nil if headers.empty?
        fields = headers.compact_map do |name, h_or_ref|
          header = h_or_ref.value || next nil
          crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(name))
          base = resolve_type(header.schema).rchop('?')
          "#{crystal_name}: #{base}?"
        end
        return nil if fields.empty?
        "{ #{fields.join(", ")} }"
      end

      # Returns a Crystal expression that parses *var_expr* (a `String?`) to the
      # correct type based on the header schema.
      private def header_parse_expr(schema_or_ref : Model::OrRef(Model::Schema)?, var_expr : String) : String
        return var_expr unless schema_or_ref
        s = schema_or_ref.value || return var_expr
        case {s.type, s.format}
        when {"integer", "int64"} then "#{var_expr}.try(&.to_i64?)"
        when {"integer", _}       then "#{var_expr}.try(&.to_i32?)"
        when {"number", "float"}  then "#{var_expr}.try(&.to_f32?)"
        when {"number", _}        then "#{var_expr}.try(&.to_f64?)"
        when {"boolean", _}       then "#{var_expr}.try { |_v| _v == \"true\" }"
        when {"string", "uuid"}   then "#{var_expr}.try { |_v| UUID.parse?(_v) }"
        else                           var_expr
        end
      end
    end
  end
end
