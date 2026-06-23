require "crystina"

module OpenAPI
  module Generator
    # :nodoc:
    abstract class ServerGenerator < Base
      include ParamValidation
      include ParamHelpers

      private alias NameInflector = Types::NameInflector
      private alias TypeMapper = Types::TypeMapper

      @doc : Model::Document? = nil

      def generate(doc : Model::Document, ctx : RenderContext) : Array(GeneratedFile)
        @doc = doc
        b = Crystina.build
        emit_header(doc, ctx, b)
        yaml_needed = needs_yaml?(doc)
        b.req(framework_require)
        b.req("json")
        b.req("yaml") if yaml_needed
        b.blank
        b.mod(ctx.namespace) do |ns_b|
          ns_b.comment("Generated handler stub. Override `around_action` to wrap every operation")
          ns_b.comment("with logging, auth, timing, or other cross-cutting behaviour. Call `yield`")
          ns_b.comment("to execute the actual dispatch; raise to abort.")
          ns_b.blank_comment
          ns_b.comment("Example:")
          ns_b.blank_comment
          ns_b.comment("```crystal", wrap: false)
          ns_b.comment("class My#{ctx.namespace}Handler < #{ctx.namespace}::Handler", wrap: false)
          ns_b.comment("  def around_action(operation : Symbol, context : #{before_action_context_type}, &block : -> Nil) : Nil", wrap: false)
          ns_b.comment("    Log.info { \"→ \#{operation}\" }", wrap: false)
          ns_b.comment("    yield", wrap: false)
          ns_b.comment("    Log.info { \"← \#{operation} \#{context.response.status_code}\" }", wrap: false)
          ns_b.comment("  end", wrap: false)
          ns_b.comment("end", wrap: false)
          ns_b.comment("```", wrap: false)
          emit_handler(doc, ns_b)
        end

        [GeneratedFile.new(ctx.output_path, b.to_s).format]
      end

      private abstract def framework_require : String
      private abstract def context_var : String
      private abstract def helpers_module : String
      private abstract def route_prefix(http_method : String) : String
      private abstract def register_def : String
      private abstract def path_param_key(name : String) : String
      private abstract def before_action_context_type : String

      private def wrap_handler(b : Crystina::Builder, &block : Crystina::Builder ->) : Nil
        block.call(b)
      end

      private def emit_handler(doc : Model::Document, b : Crystina::Builder) : Nil
        has_validation = false
        doc.each_path_item do |_, path_item|
          path_item.each_operation do |_, operation|
            has_validation = true if operation_has_validation?(operation, path_item)
          end
        end

        wrap_handler(b) do |inner_b|
          inner_b.klass(:Handler, abstract_class: true) do |klass_b|
            klass_b.mixin(helpers_module)
            klass_b.mixin("OpenAPI::Validation::Helpers") if has_validation

            doc.each_path_item do |path_template, path_item|
              path_item.each_operation do |http_method, operation|
                klass_b.blank
                emit_abstract_def(operation, http_method, path_template, path_item, klass_b)
              end
            end

            doc.each_path_item do |path_template, path_item|
              path_item.each_operation do |http_method, operation|
                klass_b.blank
                emit_validate_params_def(operation, http_method, path_template, path_item, klass_b)
              end
            end

            klass_b.blank
            klass_b.scope(register_def) do |reg_b|
              doc.each_path_item do |path_template, path_item|
                path_item.each_operation do |http_method, operation|
                  reg_b.blank
                  emit_route(path_template, http_method, operation, path_item, reg_b)
                end
              end
            end
          end
        end
      end

      private def emit_abstract_def(
        operation : Model::Operation,
        http_method : String,
        path_template : String,
        path_item : Model::PathItem,
        b : Crystina::Builder,
      ) : Nil
        if summary = operation.summary
          b.comment(summary)
          if desc = operation.description.presence
            b.blank_comment
            desc.each_line { |line| b.comment(line.chomp) }
          end
        elsif desc = operation.description.presence
          desc.each_line { |line| b.comment(line.chomp) }
        end

        error_clauses = resolve_error_clauses(operation, http_method, path_template)
        unless error_clauses.empty?
          b.blank_comment
          b.comment("Raises:")
          error_clauses.each do |http_status, type_name|
            b.comment("* `#{type_name}` — HTTP #{http_status}", wrap: false)
          end
        end

        all_params = effective_params(path_item, operation)
        path_params = all_params.select { |p| p.location == "path" }
        query_params = all_params.select { |p| p.location == "query" }
        header_params = all_params.select { |p| p.location == "header" }
        cookie_params = all_params.select { |p| p.location == "cookie" }
        body_type = resolve_request_body_type(operation, http_method, path_template)
        response_type = resolve_response_type(operation, http_method, path_template)
        resp_headers_type = resolve_response_headers_type(operation)
        mname = operation_method_name(operation.operation_id, http_method, path_template)

        full_return_type = resp_headers_type ? "{ #{response_type}, #{resp_headers_type} }" : response_type

        params = {} of String => String
        path_params.each do |p|
          crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
          params[crystal_name] = resolve_type(p.schema, p.name)
        end
        if bt = body_type
          params["body"] = bt
        end
        query_params.each do |p|
          crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
          base_type = resolve_type(p.schema, p.name).rchop('?')
          params[crystal_name] = "#{base_type}? = nil"
        end
        if !header_params.empty?
          params["headers"] = "#{named_tuple_type(header_params)}? = nil"
        end
        if !cookie_params.empty?
          params["cookies"] = "#{named_tuple_type(cookie_params)}? = nil"
        end

        b.line("@[Deprecated]") if operation.deprecated?
        b.abstract_def(mname, params, full_return_type)
      end

      private def emit_route(
        path_template : String,
        http_method : String,
        operation : Model::Operation,
        path_item : Model::PathItem,
        b : Crystina::Builder,
      ) : Nil
        converted_path = convert_path(path_template)
        mname = operation_method_name(operation.operation_id, http_method, path_template)
        response_type = resolve_response_type(operation, http_method, path_template)
        body_type = resolve_request_body_type(operation, http_method, path_template)
        success_status = success_status_code(operation)

        all_params = effective_params(path_item, operation)
        path_params = all_params.select { |p| p.location == "path" }
        query_params = all_params.select { |p| p.location == "query" }
        header_params = all_params.select { |p| p.location == "header" }
        cookie_params = all_params.select { |p| p.location == "cookie" }
        resp_headers_type = resolve_response_headers_type(operation)
        all_error_clauses = resolve_error_clauses(operation, http_method, path_template)
        rescue_clauses = dedup_error_clauses(all_error_clauses)
        ctx = context_var

        req_mode = request_body_content_mode(operation)
        resp_mode = response_content_mode(operation)

        b.rescue_block("#{route_prefix(http_method)} #{converted_path.inspect} do |#{ctx}|") do |rb|
          rb.body do |body_b|
            body_b.scope("around_action(:#{mname}, #{ctx}) do", "end") do |action_b|
              path_params.each do |p|
                crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
                emit_path_param_parse(p, crystal_name, action_b)
              end

              query_params.each do |p|
                crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
                emit_query_param_parse(p, crystal_name, action_b)
              end

              unless header_params.empty?
                header_params.each do |p|
                  crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
                  helper = "header_#{param_helper_suffix(p.schema)}"
                  action_b.assign(crystal_name, "#{helper}(#{ctx}, #{p.name.inspect})")
                end
                fields = header_params.map do |p|
                  crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
                  "#{crystal_name}: #{crystal_name}"
                end
                action_b.assign("_req_headers", "{ #{fields.join(", ")} }")
              end

              unless cookie_params.empty?
                cookie_params.each do |p|
                  crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
                  helper = "cookie_#{param_helper_suffix(p.schema)}"
                  action_b.assign(crystal_name, "#{helper}(#{ctx}, #{p.name.inspect})")
                end
                fields = cookie_params.map do |p|
                  crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
                  "#{crystal_name}: #{crystal_name}"
                end
                action_b.assign("_req_cookies", "{ #{fields.join(", ")} }")
              end

              if body_type
                if req_mode == :raw
                  action_b.assign("body").method_call("raw_body", ctx)
                elsif req_mode == :json_only
                  action_b.assign("body").method_call("parse_json_body", ctx, body_type)
                elsif req_mode == :xml_only
                  action_b.assign("body").method_call("parse_xml_body", ctx, body_type)
                elsif req_mode == :form_only
                  action_b.assign("body").method_call("parse_form_body", ctx, body_type)
                elsif req_mode == :multipart_only
                  action_b.assign("body").method_call("parse_multipart_body", ctx, body_type)
                else
                  req_content = operation.request_body.try(&.value).try(&.content)
                  has_xml_req = req_content.try(&.any? { |k, _| XML_CONTENT_TYPES.includes?(k) }) || false
                  has_yaml_req = req_content.try(&.any? { |k, _| YAML_CONTENT_TYPES.includes?(k) }) || false
                  has_form_req = req_content.try(&.has_key?("application/x-www-form-urlencoded")) || false
                  parse_helper = has_xml_req && !has_yaml_req && !has_form_req ? "xml_json_parse_body" : "parse_body"
                  action_b.assign("body").method_call(parse_helper, ctx, body_type)
                end
              end

              call_args = [] of String
              path_params.each { |p| call_args << NameInflector.safe_identifier(NameInflector.snake_case(p.name)) }
              call_args << "body" if body_type
              query_params.each { |p| call_args << NameInflector.safe_identifier(NameInflector.snake_case(p.name)) }
              call_args << "_req_headers" unless header_params.empty?
              call_args << "_req_cookies" unless cookie_params.empty?

              if resp_headers_type
                action_b.assign("_result_tuple").method_call(mname, call_args)
                action_b.assign("_body", "_result_tuple[0]")
                action_b.assign("_resp_hdrs", "_result_tuple[1]")
                resp_or_ref2 =
                  operation.responses["200"]? ||
                    operation.responses["201"]? ||
                    operation.responses.find { |k, _| k.starts_with?("2") }.try(&.last)
                (resp_or_ref2.try(&.value).try(&.headers) || {} of String => Model::OrRef(Model::Header)).each do |name, _|
                  crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(name))
                  action_b.line("_resp_hdrs[:#{crystal_name}].try { |_v| #{ctx}.response.headers[#{name.inspect}] = _v.to_s }")
                end
                result_sym = "_body"
                call_made = true
              else
                result_sym = "result"
                call_made = false
              end

              if response_type == "Nil"
                action_b.method_call(mname, call_args) unless call_made
                action_b.assign("#{ctx}.response.status_code", success_status)
              elsif response_type == "IO::Memory"
                action_b.assign(result_sym).method_call(mname, call_args) unless call_made
                action_b.method_call(:raw_response, ctx, success_status, result_sym)
              elsif resp_mode == :yaml_only
                action_b.assign(result_sym).method_call(mname, call_args) unless call_made
                action_b.method_call(:yaml_response, ctx, success_status, result_sym)
              elsif resp_mode == :xml_only
                action_b.assign(result_sym).method_call(mname, call_args) unless call_made
                action_b.method_call(:xml_response, ctx, success_status, result_sym)
              elsif resp_mode == :multi
                action_b.assign(result_sym).method_call(mname, call_args) unless call_made
                resp_content = operation.responses.values.compact_map { |r| r.value.try(&.content) }.first?
                has_xml_resp = resp_content.try(&.any? { |k, _| XML_CONTENT_TYPES.includes?(k) }) || false
                has_yaml_resp = resp_content.try(&.any? { |k, _| YAML_CONTENT_TYPES.includes?(k) }) || false
                resp_helper = has_xml_resp && !has_yaml_resp ? :xml_json_typed_response : :typed_response
                action_b.method_call(resp_helper, ctx, success_status, result_sym)
              else
                action_b.assign(result_sym).method_call(mname, call_args) unless call_made
                action_b.method_call(:json_response, ctx, success_status, result_sym)
              end
            end
          end

          rescue_clauses.each do |http_status, type_name|
            rb.rescue_clause(:ex, type_name) do |rc|
              rc.method_call(:json_error, ctx, :ex, http_status)
            end
          end

          rb.rescue_clause(:ex, "Exception") do |rc|
            rc.assign("#{ctx}.response.status_code", 500)
            rc.method_call("#{ctx}.response.print", "ex.message", braces: false)
          end
        end
      end

      private def emit_path_param_parse(
        param : Model::Parameter,
        crystal_name : String,
        b : Crystina::Builder,
      ) : Nil
        if string_enum_param?(param.schema)
          enum_type = NameInflector.pascal_case(NameInflector.safe_identifier(param.name))
          b.assign(crystal_name, "#{enum_type}.from_wire(path_string(#{context_var}, #{path_param_key(param.name)}))")
        else
          helper = "path_#{param_helper_suffix(param.schema)}"
          b.assign(crystal_name, "#{helper}(#{context_var}, #{path_param_key(param.name)})")
        end
      end

      private def emit_query_param_parse(
        param : Model::Parameter,
        crystal_name : String,
        b : Crystina::Builder,
      ) : Nil
        if string_enum_param?(param.schema)
          enum_type = NameInflector.pascal_case(NameInflector.safe_identifier(param.name))
          args = "#{context_var}, #{param.name.inspect}"
          b.assign(crystal_name, "query_string(#{args}).try { |s| #{enum_type}.from_wire(s) }")
        elsif array_schema?(param.schema)
          style, explode = effective_query_style(param)
          delimiter_arg = explode ? "nil" : query_style_delimiter(style).inspect
          raw = "query_string_array(#{context_var}, #{param.name.inspect}, #{delimiter_arg})"
          item_schema = param.schema.try(&.value).try(&.items).try(&.value)
          if item_schema && item_schema.type == "string" && item_schema.format == "uuid"
            b.assign(crystal_name, "#{raw}.try(&.map { |_s| UUID.new(_s) })")
          else
            b.assign(crystal_name, raw)
          end
        else
          helper = "query_#{param_helper_suffix(param.schema)}"
          args = "#{context_var}, #{param.name.inspect}"
          if default_lit = param_default_literal(param.schema)
            args += ", #{default_lit}"
          end
          b.assign(crystal_name, "#{helper}(#{args})")
        end
      end

      private def string_enum_param?(or_ref : Model::OrRef(Model::Schema)?) : Bool
        s = or_ref.try(&.value) || return false
        TypeMapper.string_enum?(s)
      end

      private def array_schema?(schema_or_ref : Model::OrRef(Model::Schema)?) : Bool
        schema_or_ref.try(&.value).try(&.type) == "array"
      end

      private def effective_query_style(param : Model::Parameter) : {String, Bool}
        style = param.style || "form"
        explode = param.explode.nil? || param.explode == true
        {style, explode}
      end

      private def query_style_delimiter(style : String) : String
        case style
        when "spaceDelimited" then " "
        when "pipeDelimited"  then "|"
        else                       ","
        end
      end

      private def emit_validate_params_def(
        operation : Model::Operation,
        http_method : String,
        path_template : String,
        path_item : Model::PathItem,
        b : Crystina::Builder,
      ) : Nil
        return unless operation_has_validation?(operation)

        all_params = effective_params(path_item, operation)
        constrained_path_params = all_params.select { |p| p.location == "path" && schema_has_constraints?(p.schema) }
        constrained_query_params = all_params.select { |p| p.location == "query" && (p.required? || schema_has_constraints?(p.schema)) }
        body_type = resolve_request_body_type(operation, http_method, path_template)
        validate_body = body_has_validation?(operation)
        mname = operation_method_name(operation.operation_id, http_method, path_template)

        params = {} of String => String
        constrained_path_params.each do |p|
          crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
          params[crystal_name] = resolve_type(p.schema, p.name)
        end
        if (bt = body_type) && validate_body
          params["body"] = bt
        end
        constrained_query_params.each do |p|
          crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
          base_type = resolve_type(p.schema, p.name).rchop('?')
          params[crystal_name] = "#{base_type}? = nil"
        end

        b.comment("Validates the constrained parameters for `#{mname}` and returns any violations.")
        b.blank_comment
        b.comment("Parameters:")
        constrained_path_params.each do |p|
          crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
          b.comment("* `#{crystal_name}` — #{param_constraint_summary(p.schema)}", wrap: false)
        end
        if (bt = body_type) && validate_body
          b.comment("* `body` — validated via `#{bt}#valid?`", wrap: false)
        end
        constrained_query_params.each do |p|
          crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
          b.comment("* `#{crystal_name}` — #{param_constraint_summary(p.schema, required: p.required?)}", wrap: false)
        end

        b.def_method("validate_#{mname}_params", params, "Array(OpenAPI::Validation::Error)") { |mb|
          mb.assign("errors", "[] of OpenAPI::Validation::Error")
          constrained_path_params.each do |p|
            crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
            emit_param_constraints(p.schema, p.name, crystal_name, false, false, mb)
          end
          mb.line("errors.concat(body.valid?)") if validate_body
          constrained_query_params.each do |p|
            crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
            emit_param_constraints(p.schema, p.name, crystal_name, p.required?, true, mb)
          end
          mb.line("errors")
        }
      end

      private def param_constraint_summary(schema_or_ref : Model::OrRef(Model::Schema)?, required : Bool = false) : String
        s = schema_or_ref.try(&.value)
        parts = [] of String
        parts << "required" if required
        return parts.join(", ") unless s
        if minimum = s.minimum
          parts << "minimum: #{minimum == minimum.floor ? minimum.to_i64 : minimum}"
        end
        if maximum = s.maximum
          parts << "maximum: #{maximum == maximum.floor ? maximum.to_i64 : maximum}"
        end
        parts << "minLength: #{s.min_length}" if s.min_length
        parts << "maxLength: #{s.max_length}" if s.max_length
        parts << "pattern: /#{s.pattern}/" if s.pattern
        if enum_vals = s.enum_values.try(&.as_a?)
          parts << "one of: #{enum_vals.map(&.raw.to_s).join(", ")}"
        end
        parts.join(", ")
      end

      private def param_helper_suffix(schema_or_ref : Model::OrRef(Model::Schema)?) : String
        return "string" unless schema_or_ref
        s = schema_or_ref.value || return "string"
        case {s.type, s.format}
        when {"integer", "int64"} then "int64"
        when {"integer", _}       then "int32"
        when {"number", "float"}  then "float32"
        when {"number", _}        then "float64"
        when {"boolean", _}       then "bool"
        when {"string", "uuid"}   then "uuid"
        else                           "string"
        end
      end

      private def param_default_literal(schema_or_ref : Model::OrRef(Model::Schema)?) : String?
        s = schema_or_ref.try(&.value) || return nil
        raw = s.default || return nil
        case raw.raw
        when String  then raw.raw.as(String).inspect
        when Int64   then raw.raw.as(Int64).to_s
        when Float64 then raw.raw.as(Float64).to_s
        when Bool    then raw.raw.as(Bool).to_s
        end
      end

      private def convert_path(path_template : String) : String
        path_template.gsub(/\{([^}]+)\}/, ":\\1")
      end

      private def success_status_code(operation : Model::Operation) : Int32
        ["200", "201", "202", "204"].each do |code|
          return code.to_i if operation.responses[code]?
        end
        operation.responses.each_key do |k|
          next unless k.starts_with?("2")
          return k.to_i if k.to_i?
          if code = range_status_code(k)
            return code
          end
        end
        200
      end

      private def operation_method_name(operation_id : String?, http_method : String, path_template : String) : String
        if op_id = operation_id
          NameInflector.safe_identifier(NameInflector.snake_case(op_id))
        else
          parts = path_template.split("/").compact_map do |segment|
            next nil if segment.empty?
            if segment.starts_with?('{') && segment.ends_with?('}')
              "by_#{NameInflector.snake_case(segment[1..-2])}"
            else
              NameInflector.snake_case(segment)
            end
          end
          NameInflector.safe_identifier("#{http_method}_#{parts.join("_")}")
        end
      end

      private def resolve_type(or_ref : Model::OrRef(Model::Schema)?, param_name : String? = nil) : String
        return "String" unless or_ref
        if ref = or_ref.ref
          TypeMapper.ref_name(ref)
        elsif s = or_ref.value
          if (pn = param_name) && TypeMapper.string_enum?(s)
            NameInflector.pascal_case(NameInflector.safe_identifier(pn))
          else
            TypeMapper.crystal_type(s)
          end
        else
          "String"
        end
      end

      private def resolve_response(or_ref : Model::OrRef(Model::Response)) : Model::Response?
        or_ref.value || or_ref.ref.try { |r|
          @doc.try(&.components).try(&.responses).try(&.[r.split("/").last]?).try(&.value)
        }
      end

      private def resolve_error_clauses(
        operation : Model::Operation,
        http_method : String,
        path_template : String,
      ) : Array({Int32, String})
        clauses = [] of {Int32, String}
        candidates = operation.responses
          .select { |k, _| k == "default" || !k.starts_with?("2") }
          .to_a
          .sort_by { |k, _| k == "default" ? "999" : k }
        candidates.each do |status_key, resp_or_ref|
          http_status = status_key == "default" ? 500 : (status_key.to_i? || range_status_code(status_key) || 500)
          type_name = if resp_ref = resp_or_ref.ref
                        resp_ref.split("/").last
                      else
                        response = resp_or_ref.value || next
                        content = response.content || next
                        key = pick_content_key(content) || next
                        schema_or_ref = content[key]?.try(&.schema) || next
                        if ref = schema_or_ref.ref
                          TypeMapper.ref_name(ref)
                        elsif (s = schema_or_ref.value) && s.type == "object" && s.properties
                          NameInflector.operation_error_type_name(
                            operation.operation_id, http_method, path_template, status_key)
                        end
                      end
          clauses << {http_status, type_name} if type_name
        end
        clauses
      end

      private def dedup_error_clauses(clauses : Array({Int32, String})) : Array({Int32, String})
        seen = {} of String => Int32
        clauses.each do |status, type|
          seen[type] = {seen.fetch(type, status), status}.min
        end
        seen.map { |type, status| {status, type} }.sort_by! { |s, _| s }
      end

      private def resolve_request_body_type(operation : Model::Operation, http_method : String, path_template : String) : String?
        content = operation.request_body.try(&.value).try(&.content) || return nil
        return "IO::Memory" if content_mode(content) == :raw
        key = pick_content_key(content) || return nil
        schema_or_ref = content[key]?.try(&.schema)
        if ref = schema_or_ref.try(&.ref)
          TypeMapper.ref_name(ref)
        elsif (s = schema_or_ref.try(&.value)) && s.type == "object" && s.properties
          NameInflector.operation_type_name(operation.operation_id, http_method, path_template) + "Request"
        elsif s = schema_or_ref.try(&.value)
          TypeMapper.crystal_type(s)
        else
          nil
        end
      end

      private def resolve_response_type(operation : Model::Operation, http_method : String, path_template : String) : String
        resp_or_ref =
          operation.responses["200"]? ||
            operation.responses["201"]? ||
            operation.responses.find { |k, _| k.starts_with?("2") }.try(&.last)
        return "Nil" unless resp_or_ref
        response = resp_or_ref.value || return "Nil"
        content = response.content || return "Nil"
        return "IO::Memory" if content_mode(content) == :raw
        key = pick_content_key(content) || return "Nil"
        schema_or_ref = content[key]?.try(&.schema) || return "Nil"

        if ref = schema_or_ref.ref
          TypeMapper.ref_name(ref)
        elsif (s = schema_or_ref.value) && s.type == "object" && s.properties
          NameInflector.operation_type_name(operation.operation_id, http_method, path_template) + "Response"
        elsif s = schema_or_ref.value
          TypeMapper.crystal_type(s)
        else
          "JSON::Any"
        end
      end

      private def request_body_content_mode(operation : Model::Operation) : Symbol
        content = operation.request_body.try(&.value).try(&.content)
        content_mode(content)
      end

      private def response_content_mode(operation : Model::Operation) : Symbol
        resp_or_ref =
          operation.responses["200"]? ||
            operation.responses["201"]? ||
            operation.responses.find { |k, _| k.starts_with?("2") }.try(&.last)
        response = resp_or_ref.try(&.value) || return :none
        content_mode(response.content)
      end

      private def needs_yaml?(doc : Model::Document) : Bool
        found = false
        doc.each_path_item do |_, path_item|
          path_item.each_operation do |_, operation|
            m = request_body_content_mode(operation)
            found = true if m == :yaml_only || m == :multi
            m = response_content_mode(operation)
            found = true if m == :yaml_only || m == :multi
          end
        end
        found
      end
    end
  end
end
