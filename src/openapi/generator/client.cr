require "crystina"

module OpenAPI
  module Generator
    # Generates a Crystal HTTP client with one typed method per API operation.
    class ClientGenerator < Base
      include ParamValidation
      include ParamHelpers

      private alias NameInflector = Types::NameInflector
      private alias TypeMapper = Types::TypeMapper

      @doc : Model::Document? = nil

      # Runs the generator and returns a single-element array with the generated file.
      def generate(doc : Model::Document, ctx : RenderContext) : Array(GeneratedFile)
        @doc = doc
        b = Crystina.build
        emit_header(doc, ctx, b)

        has_validation = ctx.validate_params && begin
          found = false
          doc.each_path_item { |_, pi| pi.each_operation { |_, op| found = true if operation_has_validation?(op, pi) } }
          found
        end

        yaml_needed = needs_yaml?(doc)
        form_needed = needs_form?(doc)
        multipart_needed = needs_multipart?(doc)
        b.req("http/client")
        b.req("json")
        b.req("yaml") if yaml_needed
        b.req("http/params") if form_needed
        b.req("http/formdata") if multipart_needed
        b.blank
        b.scope("module #{ctx.namespace}") do |ns_b|
          ns_b.comment("Generated HTTP client. Override `perform_request` in a subclass to add")
          ns_b.comment("logging, auth headers, retries, or any other cross-cutting behaviour.")
          ns_b.blank_comment
          ns_b.comment("Example:")
          ns_b.blank_comment
          ns_b.comment("```crystal", wrap: false)
          ns_b.comment("class My#{ctx.namespace}Client < #{ctx.namespace}::Client", wrap: false)
          ns_b.comment("  private def perform_request(operation : Symbol, request : HTTP::Request) : HTTP::Client::Response", wrap: false)
          ns_b.comment("    request.headers[\"Authorization\"] = \"Bearer \#{@token}\"", wrap: false)
          ns_b.comment("    super", wrap: false)
          ns_b.comment("  end", wrap: false)
          ns_b.comment("end", wrap: false)
          ns_b.comment("```", wrap: false)
          ns_b.scope("class Client") do |class_b|
            class_b.line("include OpenAPI::Client::Helpers")
            if has_validation
              class_b.line("include OpenAPI::Validation::Helpers")
            end
            class_b.blank
            class_b.def_method("initialize", {"@http" => "HTTP::Client"})
            doc.each_path_item do |path_template, path_item|
              path_item.each_operation do |http_method, operation|
                class_b.blank
                emit_operation(path_template, http_method, operation, path_item, ctx, class_b)
              end
            end
          end
        end

        [GeneratedFile.new(ctx.output_path, b.to_s).format]
      end

      private def emit_operation(
        path_template : String,
        http_method : String,
        operation : Model::Operation,
        path_item : Model::PathItem,
        ctx : RenderContext,
        b : Crystina::Builder,
      ) : Nil
        all_params = effective_params(path_item, operation)
        path_params = all_params.select { |p| p.location == "path" }
        query_params = all_params.select { |p| p.location == "query" }
        header_params = all_params.select { |p| p.location == "header" }
        cookie_params = all_params.select { |p| p.location == "cookie" }

        body_type = resolve_request_body_type(operation, http_method, path_template)
        response_type = resolve_response_type(operation, http_method, path_template)
        resp_headers_type = resolve_response_headers_type(operation)
        req_mode = request_body_content_mode(operation)
        resp_mode = response_content_mode(operation)
        mname = operation_method_name(operation.operation_id, http_method, path_template)
        crystal_path = build_crystal_path(path_template)

        full_return_type = resp_headers_type ? "{ #{response_type}, #{resp_headers_type} }" : response_type

        params = {} of String => String
        path_params.each do |p|
          crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
          params[crystal_name] = resolve_type(p.schema, p.name)
        end
        params["body"] = body_type if body_type
        params["content_type"] = "String = \"application/json\"" if body_type && req_mode == :multi
        query_params.each do |p|
          crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
          params[crystal_name] = "#{resolve_type(p.schema, p.name).rchop('?')}? = nil"
        end
        if !header_params.empty?
          params["headers"] = "#{named_tuple_type(header_params)}? = nil"
        end
        if !cookie_params.empty?
          params["cookies"] = "#{named_tuple_type(cookie_params)}? = nil"
        end
        if response_type != "Nil" && response_type != "IO::Memory" && resp_mode == :multi
          params["accept"] = "String = \"application/json\""
        end

        if summary = operation.summary
          b.comment(summary)
          if desc = operation.description.presence
            b.blank_comment
            desc.each_line { |line| b.comment(line.chomp) }
          end
        elsif desc = operation.description.presence
          desc.each_line { |line| b.comment(line.chomp) }
        end

        b.line("@[Deprecated]") if operation.deprecated?
        b.def_method(mname, params, full_return_type) do |method_b|
          if ctx.validate_params && operation_has_validation?(operation, path_item)
            emit_inline_param_validation(operation, path_item, method_b)
          end
          if !query_params.empty?
            method_b.assign("path", "\"#{crystal_path}\"")
            method_b.scope("query = HTTP::Params.build do |p|", "end") do |q_b|
              query_params.each do |p|
                crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
                val_expr = string_enum_param?(p.schema) ? "#{crystal_name}.try(&.wire_value)" : crystal_name
                if array_schema?(p.schema)
                  style, explode = effective_query_style(p)
                  if explode
                    q_b.line "add_exploded_param(p, #{p.name.inspect}, #{val_expr})"
                  else
                    delimiter = query_style_delimiter(style)
                    q_b.line "add_joined_param(p, #{p.name.inspect}, #{val_expr}, #{delimiter.inspect})"
                  end
                else
                  q_b.line "add_param(p, #{p.name.inspect}, #{val_expr})"
                end
              end
            end
          end
          url_arg = !query_params.empty? ? "build_url(path, query)" : "\"#{crystal_path}\""

          # Accept header expression: nil when not needed, a Crystal string otherwise.
          accept_expr = case resp_mode
                        when :json_only then "\"application/json\""
                        when :yaml_only then "\"application/yaml\""
                        when :xml_only  then "\"application/xml\""
                        when :multi     then "accept"
                        else                 nil
                        end

          need_dynamic_headers = !header_params.empty? || !cookie_params.empty?

          if body_type && form_in_query?(http_method, req_mode)
            # GET/HEAD with form body: merge form params into the URL query string.
            form_url = !query_params.empty? ? "build_url(path, query, body.to_form_params)" : "build_url(\"#{crystal_path}\", body.to_form_params)"
            base_he = accept_expr.try { |ae| "HTTP::Headers{\"Accept\" => #{ae}}" }
            he = need_dynamic_headers ? emit_dynamic_headers(header_params, cookie_params, base_he, method_b) : base_he
            emit_http_call(method_b, mname, http_method, form_url, he)
          elsif body_type
            if req_mode == :raw
              ct_expr = raw_request_content_type(operation).inspect
              body_expr = "body.rewind.gets_to_end"
            else
              req_content = operation.request_body.try(&.value).try(&.content)
              has_form_in_multi = req_content.try(&.has_key?("application/x-www-form-urlencoded")) || false
              has_xml_in_multi = req_content.try { |c| XML_CONTENT_TYPES.any? { |k| c.has_key?(k) } } || false
              helper = case req_mode
                       when :yaml_only      then "serialize_yaml_body"
                       when :xml_only       then "serialize_xml_body"
                       when :form_only      then "serialize_form_body"
                       when :multipart_only then "serialize_multipart_body"
                       when :multi
                         if has_form_in_multi
                           "serialize_body"
                         elsif has_xml_in_multi
                           "xml_json_serialize_body"
                         else
                           "yaml_json_serialize_body"
                         end
                       else "serialize_json_body"
                       end
              arg = req_mode == :multi ? "body, content_type" : "body"
              method_b.line("serialized, ct = #{helper}(#{arg})")
              ct_expr = "ct"
              body_expr = "serialized"
            end
            base_he = if ae = accept_expr
                        "HTTP::Headers{\"Content-Type\" => #{ct_expr}, \"Accept\" => #{ae}}"
                      else
                        "HTTP::Headers{\"Content-Type\" => #{ct_expr}}"
                      end
            he = need_dynamic_headers ? emit_dynamic_headers(header_params, cookie_params, base_he, method_b) : base_he
            emit_http_call(method_b, mname, http_method, url_arg, he, body_expr)
          elsif ae = accept_expr
            base_he = "HTTP::Headers{\"Accept\" => #{ae}}"
            he = need_dynamic_headers ? emit_dynamic_headers(header_params, cookie_params, base_he, method_b) : base_he
            emit_http_call(method_b, mname, http_method, url_arg, he)
          else
            if need_dynamic_headers
              he = emit_dynamic_headers(header_params, cookie_params, nil, method_b)
              emit_http_call(method_b, mname, http_method, url_arg, he)
            else
              emit_http_call(method_b, mname, http_method, url_arg)
            end
          end

          specific_errors, default_error = resolve_client_error_clauses(operation, http_method, path_template)
          if specific_errors.empty? && default_error.nil?
            method_b.raise_ex_unless("Exception.new(\"HTTP \#{response.status_code}: \#{response.body}\")", "response.success?")
          elsif specific_errors.empty?
            method_b.raise_ex_unless("#{default_error.not_nil!}.from_json(response.body)", "response.success?") # ameba:disable Lint/NotNil
          else
            spec = specific_errors
            de = default_error
            method_b.unless_block("response.success?") do
              case_when("response.status_code") do |cb|
                spec.each { |case_expr, type_name| cb.when(case_expr) { raise_ex "#{type_name}.from_json(response.body)" } }
                if d = de
                  cb.else_clause { raise_ex "#{d}.from_json(response.body)" }
                else
                  cb.else_clause { raise_ex "Exception.new(\"HTTP \#{response.status_code}: \#{response.body}\")" }
                end
              end
            end
          end

          emit_response_parse(operation, response_type, resp_mode, resp_headers_type, method_b)
        end
      end

      # Emits code to build `_req_headers` from a base expression plus any
      # named-tuple header/cookie params.  Returns the string `"_req_headers"`.
      private def emit_dynamic_headers(
        header_params : Array(Model::Parameter),
        cookie_params : Array(Model::Parameter),
        base_headers_expr : String?,
        b : Crystina::Builder,
      ) : String
        init = base_headers_expr ? "_req_headers = #{base_headers_expr}" : "_req_headers = HTTP::Headers.new"
        b.line(init)
        header_params.each do |p|
          crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
          b.line("headers.try { |_h| _h[:#{crystal_name}].try { |_v| _req_headers[#{p.name.inspect}] = _v.to_s } }")
        end
        unless cookie_params.empty?
          b.line("_cookie_parts = [] of String")
          cookie_params.each do |p|
            crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
            b.line("cookies.try { |_c| _c[:#{crystal_name}].try { |_v| _cookie_parts << \"#{p.name}=\#{_v}\" } }")
          end
          b.line("_req_headers[\"Cookie\"] = _cookie_parts.join(\"; \") unless _cookie_parts.empty?")
        end
        "_req_headers"
      end

      # Emits the response-parsing expression.  When *resp_headers_type* is set,
      # parses the body into `_body`, extracts declared response headers into
      # `_resp_hdrs`, and returns `{_body, _resp_hdrs}`.
      private def emit_response_parse(
        operation : Model::Operation,
        response_type : String,
        resp_mode : Symbol,
        resp_headers_type : String?,
        b : Crystina::Builder,
      ) : Nil
        body_expr = case {response_type, resp_mode}
                    when {"Nil", _}
                      "nil"
                    when {"IO::Memory", _}
                      "IO::Memory.new(response.body)"
                    when {_, :yaml_only}
                      "parse_yaml_response(response, #{response_type})"
                    when {_, :xml_only}
                      "parse_xml_response(response, #{response_type})"
                    when {_, :multi}
                      resp_or_ref_for_mode =
                        operation.responses["200"]? ||
                          operation.responses["201"]? ||
                          operation.responses.find { |k, _| k.starts_with?("2") }.try(&.last)
                      resp_content = resp_or_ref_for_mode.try(&.value).try(&.content)
                      has_xml_resp = resp_content.try { |c| XML_CONTENT_TYPES.any? { |k| c.has_key?(k) } } || false
                      has_yaml_resp = resp_content.try { |c| YAML_CONTENT_TYPES.any? { |k| c.has_key?(k) } } || false
                      parse_helper = if has_xml_resp && has_yaml_resp
                                       "parse_typed_response"
                                     elsif has_xml_resp
                                       "xml_json_parse_typed_response"
                                     else
                                       "yaml_json_parse_typed_response"
                                     end
                      "#{parse_helper}(response, #{response_type})"
                    else
                      "parse_json_response(response, #{response_type})"
                    end

        if resp_headers_type
          b.assign("_body", body_expr)
          resp_or_ref =
            operation.responses["200"]? ||
              operation.responses["201"]? ||
              operation.responses.find { |k, _| k.starts_with?("2") }.try(&.last)
          response_obj = resp_or_ref.try(&.value)
          raw_headers = response_obj.try(&.headers) || {} of String => Model::OrRef(Model::Header)
          fields = raw_headers.compact_map do |name, h_or_ref|
            header = h_or_ref.value || next nil
            crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(name))
            raw_expr = "response.headers[#{name.inspect}]?"
            parse_expr = header_parse_expr(header.schema, raw_expr)
            "#{crystal_name}: #{parse_expr}"
          end
          b.line("_resp_hdrs = { #{fields.join(", ")} }")
          b.line("{ _body, _resp_hdrs }")
        else
          b.line(body_expr)
        end
      end

      private def emit_inline_param_validation(operation : Model::Operation, path_item : Model::PathItem, b : Crystina::Builder) : Nil
        all_params = effective_params(path_item, operation)
        path_params = all_params.select { |p| p.location == "path" }
        query_params = all_params.select { |p| p.location == "query" }
        b.line("errors = [] of OpenAPI::Validation::Error")
        path_params.each do |p|
          next unless schema_has_constraints?(p.schema)
          crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
          emit_param_constraints(p.schema, p.name, crystal_name, false, false, b)
        end
        b.line("errors.concat(body.valid?)") if body_has_validation?(operation)
        query_params.each do |p|
          next unless p.required? || schema_has_constraints?(p.schema)
          crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(p.name))
          emit_param_constraints(p.schema, p.name, crystal_name, p.required?, true, b)
        end
        b.line("raise OpenAPI::Validation::Exception.new(errors) unless errors.empty?")
      end

      private def build_crystal_path(path_template : String) : String
        result = IO::Memory.new
        remaining = path_template
        while i = remaining.index('{')
          result << remaining[0...i]
          j = remaining.index('}', i) || break
          raw_name = remaining[(i + 1)...j]
          crystal_name = NameInflector.safe_identifier(NameInflector.snake_case(raw_name))
          result << "\#{" << crystal_name << "}"
          remaining = remaining[(j + 1)..]
        end
        result << remaining
        result.to_s
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

      private def resolve_response(or_ref : Model::OrRef(Model::Response)) : Model::Response?
        or_ref.value || or_ref.ref.try { |r|
          @doc.try(&.components).try(&.responses).try(&.[r.split("/").last]?).try(&.value)
        }
      end

      private def resolve_client_error_clauses(
        operation : Model::Operation,
        http_method : String,
        path_template : String,
      ) : {Array({String, String}), String?}
        specific = [] of {String, String}
        default_type = nil.as(String?)
        candidates = operation.responses.select { |k, _| k == "default" || !k.starts_with?("2") }.to_a
        candidates.sort_by! { |k, _| k }
        candidates.each do |status_key, resp_or_ref|
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
          next unless type_name
          if status_key == "default"
            default_type = type_name
          elsif specific_code = status_key.to_i?
            specific << {specific_code.to_s, type_name}
          elsif rc = range_status_code(status_key)
            specific << {"#{rc}..#{rc + 99}", type_name}
          end
        end
        {specific, default_type}
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

      private def form_in_query?(http_method : String, req_mode : Symbol) : Bool
        (http_method == "get" || http_method == "head") && req_mode == :form_only
      end

      # Emits a `_req = HTTP::Request.new(...)` assignment followed by
      # `response = perform_request(:op, _req)`.
      private def emit_http_call(b : Crystina::Builder, op : String, http_method : String,
                                 url_expr : String, headers_expr : String? = nil,
                                 body_expr : String? = nil) : Nil
        verb = http_method.upcase.inspect
        if headers_expr.nil?
          b.assign("_req", "HTTP::Request.new(#{verb}, #{url_expr})")
        elsif body_expr.nil?
          b.assign_call("_req", "HTTP::Request.new") do |a|
            a.line "#{verb},"
            a.line "#{url_expr},"
            a.line "#{headers_expr},"
          end
        else
          b.assign_call("_req", "HTTP::Request.new") do |a|
            a.line "#{verb},"
            a.line "#{url_expr},"
            a.line "#{headers_expr},"
            a.line "#{body_expr},"
          end
        end
        b.assign("response", "perform_request(:#{op}, _req)")
      end

      private def request_has_yaml?(operation : Model::Operation) : Bool
        content = operation.request_body.try(&.value).try(&.content) || return false
        content.any? { |k, _| YAML_CONTENT_TYPES.includes?(k) }
      end

      private def request_has_form?(operation : Model::Operation) : Bool
        operation.request_body.try(&.value).try(&.content)
          .try(&.has_key?("application/x-www-form-urlencoded")) || false
      end

      private def response_content_mode(operation : Model::Operation) : Symbol
        resp_or_ref =
          operation.responses["200"]? ||
            operation.responses["201"]? ||
            operation.responses.find { |k, _| k.starts_with?("2") }.try(&.last)
        response = resp_or_ref.try(&.value) || return :none
        content_mode(response.content)
      end

      private def raw_request_content_type(operation : Model::Operation) : String
        content = operation.request_body.try(&.value).try(&.content) || return "application/octet-stream"
        content.first_key? || "application/octet-stream"
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

      private def needs_form?(doc : Model::Document) : Bool
        found = false
        doc.each_path_item do |_, path_item|
          path_item.each_operation do |_, operation|
            m = request_body_content_mode(operation)
            found = true if m == :form_only || m == :multi
          end
        end
        found
      end

      private def needs_multipart?(doc : Model::Document) : Bool
        found = false
        doc.each_path_item do |_, path_item|
          path_item.each_operation do |_, operation|
            found = true if request_body_content_mode(operation) == :multipart_only
          end
        end
        found
      end
    end
  end
end
