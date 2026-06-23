module OpenAPI
  module Generator
    # Shared helpers for detecting OpenAPI parameter constraints and emitting
    # the corresponding `validate_*` calls into generated Crystal code.
    # Included by both `ClientGenerator` and `ServerGenerator`.
    module ParamValidation
      private alias NameInflector = Types::NameInflector
      private alias TypeMapper = Types::TypeMapper

      JSON_CONTENT_TYPES     = ["application/json", "text/json"]
      YAML_CONTENT_TYPES     = ["application/yaml", "text/yaml", "application/x-yaml", "text/x-yaml"]
      XML_CONTENT_TYPES      = ["application/xml", "text/xml"]
      MULTIPART_CONTENT_TYPE = "multipart/form-data"

      # Returns the content-map key to use for schema resolution.
      # Prefers application/json > text/json > application/yaml > text/yaml >
      # application/x-yaml > text/x-yaml > application/xml > text/xml >
      # application/x-www-form-urlencoded > multipart/form-data > first key.
      private def pick_content_key(content : Hash(String, Model::MediaType)) : String?
        JSON_CONTENT_TYPES.each { |k| return k if content.has_key?(k) }
        YAML_CONTENT_TYPES.each { |k| return k if content.has_key?(k) }
        XML_CONTENT_TYPES.each { |k| return k if content.has_key?(k) }
        return "application/x-www-form-urlencoded" if content.has_key?("application/x-www-form-urlencoded")
        return MULTIPART_CONTENT_TYPE if content.has_key?(MULTIPART_CONTENT_TYPE)
        content.first_key?
      end

      # Categorises the serialization mode implied by a content map.
      # Returns :json_only, :yaml_only, :xml_only, :form_only, :multipart_only,
      # :multi (two or more of json/yaml/xml/form/multipart present),
      # :raw (other content type), or :none (nil/empty).
      private def content_mode(content : Hash(String, Model::MediaType)?) : Symbol
        return :none if content.nil? || content.empty?
        has_json = content.any? { |k, _| JSON_CONTENT_TYPES.includes?(k) }
        has_yaml = content.any? { |k, _| YAML_CONTENT_TYPES.includes?(k) }
        has_xml = content.any? { |k, _| XML_CONTENT_TYPES.includes?(k) }
        has_form = content.has_key?("application/x-www-form-urlencoded")
        has_multipart = content.has_key?(MULTIPART_CONTENT_TYPE)
        return :multi if {has_json, has_yaml, has_xml, has_form, has_multipart}.count(&.itself) > 1
        return :json_only if has_json
        return :yaml_only if has_yaml
        return :xml_only if has_xml
        return :form_only if has_form
        return :multipart_only if has_multipart
        :raw
      end

      # Maps wildcard range keys ("1XX"–"5XX", case-insensitive) to their representative
      # HTTP status code. Returns nil for specific numeric codes, "default", or other keys.
      private def range_status_code(k : String) : Int32?
        return nil unless k.size == 3 && k[1].upcase == 'X' && k[2].upcase == 'X'
        k[0].to_i?.try { |d| d * 100 }
      end

      private def schema_has_constraints?(or_ref : Model::OrRef(Model::Schema)?) : Bool
        s = or_ref.try(&.value) || return false
        !s.minimum.nil? || !s.maximum.nil? || !s.min_length.nil? || !s.max_length.nil? ||
          !s.pattern.nil? || !s.multiple_of.nil? || s.unique_items == true ||
          !s.min_properties.nil? || !s.max_properties.nil? ||
          (!s.enum_values.nil? && !TypeMapper.string_enum?(s))
      end

      private def ref_schema_has_valid_method?(ref : String) : Bool
        ref_name = ref.split("/").last
        schema = @doc.try(&.components).try(&.schemas).try(&.[ref_name]?).try(&.value) || return false
        (schema.properties || {} of String => Model::OrRef(Model::Schema)).any? { |_, or_ref|
          schema_has_constraints?(or_ref)
        }
      end

      private def body_has_validation?(operation : Model::Operation) : Bool
        content = operation.request_body.try(&.value).try(&.content) || return false
        key = pick_content_key(content) || return false
        ref = content[key]?.try(&.schema).try(&.ref) || return false
        ref_schema_has_valid_method?(ref)
      end

      # Returns the effective parameter list for an operation, merging path-item-level
      # parameters (defaults) with operation-level parameters (overrides). Operation
      # params with the same {name, in} pair take precedence over path-item params.
      # Both inline and $ref parameters are resolved; unresolvable refs are skipped.
      private def effective_params(
        path_item : Model::PathItem?,
        operation : Model::Operation,
      ) : Array(Model::Parameter)
        base = resolve_params(path_item.try(&.parameters))
        over = resolve_params(operation.parameters)
        overridden = over.map { |p| {p.name, p.location} }.to_set
        base.reject { |p| overridden.includes?({p.name, p.location}) } + over
      end

      private def resolve_params(list : Array(Model::OrRef(Model::Parameter))?) : Array(Model::Parameter)
        (list || [] of Model::OrRef(Model::Parameter)).compact_map do |or_ref|
          or_ref.value || or_ref.ref.try { |r|
            @doc.try(&.components).try(&.parameters).try(&.[r.split("/").last]?).try(&.value)
          }
        end
      end

      private def operation_has_validation?(
        operation : Model::Operation,
        path_item : Model::PathItem? = nil,
      ) : Bool
        all_params = effective_params(path_item, operation)
        all_params.any? { |p|
          schema_has_constraints?(p.schema) || (p.location == "query" && p.required?)
        } || body_has_validation?(operation)
      end

      private def emit_param_constraints(
        schema_or_ref : Model::OrRef(Model::Schema)?,
        field_name : String,
        crystal_name : String,
        required : Bool,
        nullable : Bool,
        b : Crystina::Builder,
      ) : Nil
        b.line("validate_required errors, #{field_name.inspect}, #{crystal_name}") if required
        return unless schema_has_constraints?(schema_or_ref)
        s = schema_or_ref.try(&.value) || return
        # Crystal cannot infer T in `forall T` helpers when the argument is T | Nil.
        # For nullable params, unwrap with `if val = param` so helpers receive a concrete T.
        if nullable
          b.scope("if #{crystal_name}_val = #{crystal_name}") { |ib|
            emit_param_constraint_calls(s, field_name, "#{crystal_name}_val", ib)
          }
        else
          emit_param_constraint_calls(s, field_name, crystal_name, b)
        end
      end

      private def emit_param_constraint_calls(
        s : Model::Schema,
        field_name : String,
        crystal_name : String,
        b : Crystina::Builder,
      ) : Nil
        if min_length = s.min_length
          b.line("validate_min_length errors, #{field_name.inspect}, #{crystal_name}, #{min_length}")
        end
        if max_length = s.max_length
          b.line("validate_max_length errors, #{field_name.inspect}, #{crystal_name}, #{max_length}")
        end
        if pattern = s.pattern
          safe_pattern = pattern.gsub(/(?<!\\)\//, "\\/")
          b.line("validate_pattern errors, #{field_name.inspect}, #{crystal_name}, /#{safe_pattern}/, #{pattern.inspect}")
        end
        if minimum = s.minimum
          excl = s.exclusive_minimum ? ", true" : ""
          b.line("validate_minimum errors, #{field_name.inspect}, #{crystal_name}, #{numeric_param_literal(minimum, s)}#{excl}")
        end
        if maximum = s.maximum
          excl = s.exclusive_maximum ? ", true" : ""
          b.line("validate_maximum errors, #{field_name.inspect}, #{crystal_name}, #{numeric_param_literal(maximum, s)}#{excl}")
        end
        if multiple_of = s.multiple_of
          b.line("validate_multiple_of errors, #{field_name.inspect}, #{crystal_name}, #{numeric_param_literal(multiple_of, s)}")
        end
        if s.unique_items
          b.line("validate_unique_items errors, #{field_name.inspect}, #{crystal_name}")
        end
        if min_properties = s.min_properties
          b.line("validate_min_properties errors, #{field_name.inspect}, #{crystal_name}, #{min_properties}")
        end
        if max_properties = s.max_properties
          b.line("validate_max_properties errors, #{field_name.inspect}, #{crystal_name}, #{max_properties}")
        end
        if !TypeMapper.string_enum?(s) && (enum_vals = s.enum_values.try(&.as_a?))
          allowed_inspect = enum_vals.map(&.raw.inspect).join(", ")
          b.line("validate_enum errors, #{field_name.inspect}, #{crystal_name}, [#{allowed_inspect}]")
        end
      end

      private def numeric_param_literal(value : Float64, schema : Model::Schema) : String
        case {schema.type, schema.format}
        when {"integer", "int64"} then "#{value.to_i64}_i64"
        when {"integer", _}       then "#{value.to_i32}_i32"
        when {"number", "float"}  then "#{value.to_f32}_f32"
        when {"number", _}        then value == value.floor ? "#{value.to_i64}.0" : value.to_s
        else                           value == value.floor ? value.to_i64.to_s : value.to_s
        end
      end
    end
  end
end
