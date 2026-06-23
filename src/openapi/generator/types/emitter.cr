module OpenAPI
  module Generator
    module Types
      # :nodoc:
      class Emitter
        def initialize(
          @hooks : Hooks,
          @formats : Set(String) = Set{"json", "yaml"},
          @schema_index : Hash(String, Model::Schema) = {} of String => Model::Schema,
          @form_serializer : String = "OpenAPI::Form::Serializable",
        )
        end

        def emit(cs : ClassifiedSchema, b : Crystina::Builder) : Nil
          case cs.kind
          when .scalar_alias?    then emit_scalar_alias(cs.name, cs.schema, b)
          when .enum?            then emit_enum(cs.name, cs.schema, b)
          when .extensible_enum? then emit_extensible_enum(cs.name, cs.schema, b)
          when .struct?
            cs.source.error? ? emit_class(cs.name, cs.schema, b, cs.source) : emit_struct(cs.name, cs.schema, b)
          when .class?          then emit_class(cs.name, cs.schema, b, cs.source)
          when .abstract_class? then emit_abstract_class(cs.name, cs.schema, b)
          when .any_alias?      then emit_any_alias(cs.name, cs.schema, b)
          when .union_alias?    then emit_union_alias(cs.name, cs.schema, b)
          when .compose_alias?  then emit_compose_alias(cs.name, cs.schema, b)
          when .array_alias?    then emit_array_alias(cs.name, cs.schema, b)
          when .error_wrapper?  then emit_error_wrapper(cs.name, cs.schema, b)
          when .skip?           then return
          end
          @hooks.after_type(cs.name, cs.kind, b)
        end

        private def emit_description(schema : Model::Schema, b : Crystina::Builder) : Nil
          emit_description(schema.description, b)
        end

        private def emit_description(text : String?, b : Crystina::Builder) : Nil
          desc = text.try(&.strip)
          return if desc.nil? || desc.empty?
          desc.each_line do |raw_line|
            line = raw_line.rstrip
            if line.blank?
              b.blank_comment
            else
              b.comment(line)
            end
          end
        end

        private def resolve_crystal_type(schema : Model::Schema, name : String? = nil) : String
          if name && (override = @hooks.crystal_type_for(name, schema))
            return override
          end
          if t = schema.type
            @hooks.format_type_for(t, schema.format) || TypeMapper.crystal_type(schema)
          else
            TypeMapper.crystal_type(schema)
          end
        end

        private def emit_error_wrapper(name : String, schema : Model::Schema, b : Crystina::Builder) : Nil
          crystal_name = @hooks.crystal_name(name)
          parent = schema.all_of
            .try(&.first?.try(&.ref))
            .try { |r| TypeMapper.ref_name(r) } || "Exception"
          emit_description(schema, b)
          b.line("class #{crystal_name} < #{parent}; end")
          b.blank
        end

        private def emit_scalar_alias(name : String, schema : Model::Schema, b : Crystina::Builder) : Nil
          crystal_name = @hooks.crystal_name(name)
          crystal_type = if all_of = schema.all_of
                           if all_of.size == 1 && (ref = all_of.first.ref)
                             TypeMapper.ref_name(ref)
                           else
                             resolve_crystal_type(schema, name)
                           end
                         elsif (variants = schema.one_of || schema.any_of) && variants.size == 1
                           if ref = variants.first.ref
                             TypeMapper.ref_name(ref)
                           else
                             resolve_crystal_type(schema, name)
                           end
                         else
                           resolve_crystal_type(schema, name)
                         end

          ap_key_name = schema.additional_properties.try(&.schema).try(&.value).try(&.x_additional_properties_name)
          emit_description(schema, b)
          b.comment("Keys: #{ap_key_name}") if ap_key_name
          b.type_alias(crystal_name, crystal_type)
          b.blank
        end

        private def emit_enum(name : String, schema : Model::Schema, b : Crystina::Builder) : Nil
          crystal_name = @hooks.crystal_name(name)
          values = schema.enum_values.try(&.as_a?) || [] of JSON::Any

          first = values.first?
          is_string_enum = first.nil? || !first.as_s?.nil?

          wire_to_crystal = build_wire_map(values)

          enum_descs = schema.x_enum_descriptions.try(&.as_h?).try { |h|
            h.each_with_object({} of String => String) { |(k, v), m|
              m[k] = v.as_s? || ""
            }
          }

          emit_description(schema, b)
          extra = format_macro_args_inline
          header = extra.empty? ? "openapi_enum #{crystal_name} do" : "openapi_enum #{crystal_name}, #{extra} do"
          b.scope(header) { |eb|
            wire_to_crystal.each do |wire, cv|
              if (d = enum_descs.try(&.[wire]?)) && !d.empty?
                emit_description(d, eb)
              end
              if is_string_enum
                eb.line(wire == cv ? cv : "#{cv} = #{wire.inspect}")
              else
                eb.line("#{cv} = #{wire}")
              end
            end
          }
          b.blank
        end

        private def emit_extensible_enum(name : String, schema : Model::Schema, b : Crystina::Builder) : Nil
          crystal_name = @hooks.crystal_name(name)
          values = schema.x_extensible_enum.try(&.as_a?) || [] of JSON::Any

          wire_to_crystal = build_wire_map(values)

          enum_descs = schema.x_enum_descriptions.try(&.as_h?).try { |h|
            h.each_with_object({} of String => String) { |(k, v), m|
              m[k] = v.as_s? || ""
            }
          }

          emit_description(schema, b)
          extra = format_macro_args_inline
          header = extra.empty? ? "openapi_extensible_enum #{crystal_name} do" : "openapi_extensible_enum #{crystal_name}, #{extra} do"
          b.scope(header) { |eb|
            wire_to_crystal.each do |wire, cv|
              if (d = enum_descs.try(&.[wire]?)) && !d.empty?
                emit_description(d, eb)
              end
              eb.line(wire == cv ? cv : "#{cv} = #{wire.inspect}")
            end
          }
          b.blank
        end

        private def bool_enum?(values : Array(JSON::Any)) : Bool
          !values.empty? && values.all? { |v| !v.as_bool?.nil? }
        end

        private def build_wire_map(values : Array(JSON::Any)) : Hash(String, String)
          wire_to_crystal = {} of String => String
          values.each do |v|
            wire = v.as_s? || v.as_i?.try(&.to_s) || v.as_f?.try(&.to_s) || v.as_bool?.try { |b| b ? "true" : "false" } || "unknown"
            crystal_val = if wire.chars.select(&.letter?).all?(&.uppercase?)
                            NameInflector.safe_identifier(wire)
                          else
                            NameInflector.pascal_case(NameInflector.safe_identifier(wire))
                          end
            crystal_val = "V#{crystal_val}" if crystal_val.empty?
            crystal_val = crystal_val[0].upcase.to_s + crystal_val[1..] unless crystal_val[0]?.try(&.ascii_uppercase?)
            base = crystal_val
            i = 2
            while wire_to_crystal.values.includes?(crystal_val)
              crystal_val = "#{base}#{i}"
              i += 1
            end
            wire_to_crystal[wire] = crystal_val
          end
          wire_to_crystal
        end

        private def has_binary_props?(props : Array(Tuple(String, Model::OrRef(Model::Schema), Bool))) : Bool
          props.any? { |_, or_ref, _| or_ref.value.try(&.format) == "binary" }
        end

        private def emit_format_includes(b : Crystina::Builder, props : Array(Tuple(String, Model::OrRef(Model::Schema), Bool)) = [] of Tuple(String, Model::OrRef(Model::Schema), Bool), has_binary : Bool = false) : Nil
          unless has_binary
            b.mixin("JSON::Serializable") if @formats.includes?("json")
            b.mixin("YAML::Serializable") if @formats.includes?("yaml")
            b.mixin("OpenAPI::XML::Serializable") if @formats.includes?("xml")
            b.mixin(@form_serializer) if @formats.includes?("form")
          end
          b.mixin("OpenAPI::Multipart::Serializable") if @formats.includes?("multipart")
          b.mixin("OpenAPI::Validation::Helpers") if needs_validation_mixin?(props)
        end

        private def needs_validation_mixin?(props : Array(Tuple(String, Model::OrRef(Model::Schema), Bool))) : Bool
          props.any? { |prop_name, or_ref, _|
            s = or_ref.value || next false
            has_constraints?(s) && !(s.enum_values && inline_type(prop_name, or_ref))
          }
        end

        private def emit_struct(name : String, schema : Model::Schema, b : Crystina::Builder) : Nil
          crystal_name = @hooks.crystal_name(name)
          emit_description(schema, b)
          if @formats.includes?("xml") && (xml_name = schema.xml.try(&.name))
            b.annotate("OpenAPI::XML::Element", "name: #{xml_name.inspect}")
          end
          b.scope("struct #{crystal_name}") { |sb|
            props = collect_properties(schema, nil)
            emit_format_includes(sb, props, has_binary_props?(props))
            sb.blank
            emit_inline_classes(props, sb)
            emit_properties_from_list(props, sb)
            emit_initialize(props, sb)
            emit_validation_methods(props, sb)
            emit_strip_methods(props, sb)
          }
          b.blank
        end

        private def emit_class(name : String, schema : Model::Schema, b : Crystina::Builder, source : SchemaSource = SchemaSource::Components) : Nil
          crystal_name = @hooks.crystal_name(name)
          base_class = resolve_base_class(schema)
          base_class ||= "Exception" if source.error?
          composed_from = resolve_composed_from(schema)

          emit_description(schema, b)
          b.comment("Composed from: #{composed_from.join(", ")}") if composed_from
          if @formats.includes?("xml") && (xml_name = schema.xml.try(&.name))
            b.annotate("OpenAPI::XML::Element", "name: #{xml_name.inspect}")
          end

          if base_class == "Exception"
            props = collect_properties(schema, base_class)
            extra = format_macro_args_inline
            header = extra.empty? ? "openapi_exception #{crystal_name} do" : "openapi_exception #{crystal_name}, #{extra} do"
            b.scope(header) { |eb|
              emit_inline_classes(props, eb)
              emit_properties_from_list(props, eb)
              emit_initialize(props, eb)
              emit_validation_methods(props, eb)
            }
            b.blank
          else
            klass_header = base_class ? "#{crystal_name} < #{base_class}" : crystal_name
            b.scope("class #{klass_header}") { |kb|
              props = collect_properties(schema, base_class)
              # Error subclasses that inherit from a named exception type must not
              # include JSON::Serializable directly — JSON::Serializable picks up
              # all inherited instance vars including @cause and @callstack from
              # Crystal's Exception class which have no to_json(JSON::Builder).
              # The parent openapi_exception macro's forward_missing_to @body
              # already provides to_json delegation.
              unless source.error? && base_class
                emit_format_includes(kb, props, has_binary_props?(props))
                kb.blank
              end
              emit_inline_classes(props, kb)
              emit_properties_from_list(props, kb)
              emit_initialize(props, kb) if base_class.nil?
              emit_validation_methods(props, kb)
              emit_strip_methods(props, kb)
            }
            b.blank
          end
        end

        # Returns keyword args to append to openapi_union / openapi_allof macro calls
        # for any formats beyond JSON that the generated file requires.
        private def format_macro_args : String
          parts = [] of String
          parts << "yaml: true" if @formats.includes?("yaml")
          parts << "xml: true" if @formats.includes?("xml")
          parts << "form: #{@form_serializer}" if @formats.includes?("form")
          parts << "multipart: true" if @formats.includes?("multipart")
          parts.join(",\n  ")
        end

        # Returns keyword args for openapi_enum / openapi_extensible_enum macro headers
        # (single-line variant — enum headers cannot span multiple lines via b.scope).
        private def format_macro_args_inline : String
          parts = [] of String
          parts << "yaml: true" if @formats.includes?("yaml")
          parts << "xml: true" if @formats.includes?("xml")
          parts << "form: #{@form_serializer}" if @formats.includes?("form")
          parts << "multipart: true" if @formats.includes?("multipart")
          parts.join(", ")
        end

        private def emit_abstract_class(name : String, schema : Model::Schema, b : Crystina::Builder) : Nil
          crystal_name = @hooks.crystal_name(name)
          disc = schema.discriminator || return

          variants = [] of String
          (schema.one_of || schema.any_of).try(&.each { |r|
            r.ref.try { |ref| variants << TypeMapper.ref_name(ref) }
          })

          wire_to_type = if mapping = disc.mapping
                           mapping.map { |wire, ref_path| {wire, @hooks.crystal_name(TypeMapper.ref_name(ref_path))} }
                         else
                           variants.map { |v| {v, v} }
                         end

          mapping_str = wire_to_type.map { |wire, type| "#{wire.inspect} => #{type}" }.join(", ")
          emit_description(schema, b)
          extra = format_macro_args
          b.line("openapi_union #{crystal_name}, { #{variants.join(", ")} },")
          b.line("  discriminator: #{disc.property_name.inspect},")
          if extra.empty?
            b.line("  mapping: { #{mapping_str} }")
          else
            b.line("  mapping: { #{mapping_str} },")
            b.line("  #{extra}")
          end
          b.blank
        end

        private def emit_any_alias(name : String, schema : Model::Schema, b : Crystina::Builder) : Nil
          crystal_name = @hooks.crystal_name(name)
          variants = [] of String
          schema.one_of.try(&.each { |r| r.ref.try { |ref| variants << TypeMapper.ref_name(ref) } })
          schema.any_of.try(&.each { |r| r.ref.try { |ref| variants << TypeMapper.ref_name(ref) } })

          emit_description(schema, b)
          b.comment("Variants: #{variants.join(", ")}") unless variants.empty?
          b.comment("not: Crystal has no negation type — mapped to JSON::Any") if schema.not_schema
          b.type_alias(crystal_name, "JSON::Any")
          b.blank
        end

        private def emit_compose_alias(name : String, schema : Model::Schema, b : Crystina::Builder) : Nil
          crystal_name = @hooks.crystal_name(name)
          refs = [] of String
          (schema.all_of || [] of Model::OrRef(Model::Schema)).each do |r|
            if ref = r.ref
              refs << TypeMapper.ref_name(ref)
            end
          end
          emit_description(schema, b)
          extra = format_macro_args
          if extra.empty?
            b.line("openapi_allof #{crystal_name}, {#{refs.join(", ")}}")
          else
            b.line("openapi_allof #{crystal_name}, {#{refs.join(", ")}},")
            b.line("  #{extra}")
          end
          b.blank
        end

        private def emit_union_alias(name : String, schema : Model::Schema, b : Crystina::Builder) : Nil
          crystal_name = @hooks.crystal_name(name)
          variants = [] of String
          (schema.one_of || schema.any_of).try(&.each { |r|
            r.ref.try { |ref| variants << TypeMapper.ref_name(ref) }
          })
          emit_description(schema, b)
          extra = format_macro_args
          if extra.empty?
            b.line("openapi_union #{crystal_name}, { #{variants.join(", ")} }")
          else
            b.line("openapi_union #{crystal_name}, { #{variants.join(", ")} },")
            b.line("  #{extra}")
          end
          b.blank
        end

        private def emit_array_alias(name : String, schema : Model::Schema, b : Crystina::Builder) : Nil
          crystal_name = @hooks.crystal_name(name)

          if hash_type = TypeMapper.additional_properties_hash_type(schema)
            ap_key_name = schema.additional_properties.try(&.schema).try(&.value).try(&.x_additional_properties_name)
            emit_description(schema, b)
            b.comment("Keys: #{ap_key_name}") if ap_key_name
            b.type_alias(crystal_name, hash_type)
            b.blank
            return
          end

          item_type = if items = schema.items
                        if ref = items.ref
                          TypeMapper.ref_name(ref)
                        elsif s = items.value
                          resolve_crystal_type(s)
                        else
                          "JSON::Any"
                        end
                      else
                        "JSON::Any"
                      end

          resolved_array_type = @hooks.crystal_type_for(name, schema) || "Array(#{item_type})"
          emit_description(schema, b)
          b.type_alias(crystal_name, resolved_array_type)
          b.blank
        end

        private def emit_properties_from_list(
          props : Array(Tuple(String, Model::OrRef(Model::Schema), Bool)),
          b : Crystina::Builder,
        ) : Nil
          required = props.select { |_, _, req| req }
          optional = props.reject { |_, _, req| req }
          (required + optional).each do |prop_name, or_ref, req|
            emit_property(prop_name, or_ref, req, b)
          end
        end

        private def emit_initialize(
          props : Array(Tuple(String, Model::OrRef(Model::Schema), Bool)),
          b : Crystina::Builder,
        ) : Nil
          return if props.empty?
          required = props.select { |_, _, req| req }
          optional = props.reject { |_, _, req| req }
          req_no_default, req_with_default = required.partition { |prop_name, or_ref, req|
            resolve_type_and_default(or_ref, req, prop_name)[1].empty?
          }
          all = req_no_default + req_with_default + optional

          params = {} of String => String
          all.each do |prop_name, or_ref, req|
            crystal_prop = @hooks.property_name(prop_name)
            type_str, default_expr = resolve_type_and_default(or_ref, req, prop_name)
            if or_ref.value.try { |s| s.read_only? || s.write_only? }
              type_str = type_str.rchop('?') + "?"
              default_expr = " = nil" if default_expr.empty?
            end
            params["@#{crystal_prop}"] = "#{type_str}#{default_expr}"
          end

          b.blank
          b.def_method("initialize", params) { |_| }
        end

        private def collect_properties(
          schema : Model::Schema,
          base_class : String?,
        ) : Array(Tuple(String, Model::OrRef(Model::Schema), Bool))
          result = [] of Tuple(String, Model::OrRef(Model::Schema), Bool)
          seen = Set(String).new

          add_props = ->(props : Hash(String, Model::OrRef(Model::Schema)), req : Set(String)) {
            props.each do |prop_name, or_ref|
              unless seen.includes?(prop_name)
                seen.add(prop_name)
                result << {prop_name, or_ref, req.includes?(prop_name)}
              end
            end
          }

          req_set = (schema.required || [] of String).to_set
          schema.properties.try { |p| add_props.call(p, req_set) }

          schema.all_of.try(&.each do |entry|
            if entry.ref?
              ref_name = TypeMapper.ref_name(entry.ref || raise "ref expected")
              next if base_class == ref_name
              if ref_schema = @schema_index[ref_name]?
                ref_req = (ref_schema.required || [] of String).to_set
                ref_schema.properties.try { |p| add_props.call(p, ref_req) }
              end
              next
            end
            if inline = entry.value
              inline_req = (inline.required || [] of String).to_set
              inline.properties.try { |p| add_props.call(p, inline_req) }
            end
          end)

          result
        end

        private def emit_property(
          name : String,
          or_ref : Model::OrRef(Model::Schema),
          required : Bool,
          b : Crystina::Builder,
        ) : Nil
          crystal_prop = @hooks.property_name(name)
          prop_schema = or_ref.value
          type_str, default_expr = resolve_type_and_default(or_ref, required, name)

          if prop_schema.try { |s| s.read_only? || s.write_only? }
            type_str = type_str.rchop('?') + "?"
            default_expr = " = nil" if default_expr.empty?
          end

          emit_description(prop_schema.try(&.description), b)

          ap_key_name = prop_schema.try { |s|
            s.additional_properties.try(&.schema).try(&.value).try(&.x_additional_properties_name)
          }
          b.comment("Keys: #{ap_key_name}") if ap_key_name

          if prop_schema.try(&.format) == "byte" && @formats.includes?("json")
            json_parts = ["converter: OpenAPI::Converter::Base64"]
            json_parts.unshift("key: #{name.inspect}") if name != crystal_prop
            b.annotate("JSON::Field", json_parts.join(", "))
          elsif name != crystal_prop
            b.annotate("JSON::Field", "key: #{name.inspect}") if @formats.includes?("json")
            b.annotate("YAML::Field", "key: #{name.inspect}") if @formats.includes?("yaml")
          end

          if @formats.includes?("xml")
            xml_meta = prop_schema.try(&.xml)
            xml_parts = [] of String
            if (xname = xml_meta.try(&.name)) && xname != name
              xml_parts << "key: #{xname.inspect}"
            end
            xml_parts << "attribute: true" if xml_meta.try(&.attribute?)
            if prop_schema.try(&.type) == "array"
              xml_parts << "wrapped: true" if xml_meta.try(&.wrapped?)
              item_xml_name = prop_schema.try(&.items).try(&.value).try(&.xml).try(&.name)
              xml_parts << "item_key: #{item_xml_name.inspect}" if item_xml_name
            end
            b.annotate("OpenAPI::XML::Field", xml_parts.join(", ")) unless xml_parts.empty?
          end

          b.line("getter #{crystal_prop} : #{type_str}#{default_expr}")
        end

        private def resolve_type_and_default(
          or_ref : Model::OrRef(Model::Schema),
          required : Bool,
          prop_name : String? = nil,
        ) : {String, String}
          prop_schema = or_ref.value
          base_type = if ref = or_ref.ref
                        TypeMapper.ref_name(ref)
                      elsif s = prop_schema
                        inline_type(prop_name, or_ref) || resolve_crystal_type(s)
                      else
                        "JSON::Any"
                      end

          schema_nullable = prop_schema.try(&.nullable?) || false
          raw_default = prop_schema.try(&.default)
          default_literal = raw_default.try { |d| crystal_literal(d, base_type) }

          nullable = schema_nullable || (!required && default_literal.nil?)
          type_str = nullable ? "#{base_type}?" : base_type
          default_expr = default_literal ? " = #{default_literal}" : nullable ? " = nil" : ""
          {type_str, default_expr}
        end

        PRIMITIVE_CRYSTAL_TYPES = %w[String Int32 Int64 Float32 Float64 Bool Time UUID URI Bytes IO JSON::Any]

        private def crystal_literal(val : JSON::Any, crystal_type : String) : String?
          case raw = val.raw
          when String
            if PRIMITIVE_CRYSTAL_TYPES.includes?(crystal_type)
              raw.inspect
            else
              member = if raw.chars.select(&.letter?).all?(&.uppercase?)
                         NameInflector.safe_identifier(raw)
                       else
                         NameInflector.pascal_case(NameInflector.safe_identifier(raw))
                       end
              member = member[0].upcase.to_s + member[1..] unless member[0]?.try(&.ascii_uppercase?)
              "#{crystal_type}::#{member}"
            end
          when Bool    then raw.to_s
          when Int64   then crystal_type == "Int64" ? "#{raw}_i64" : raw.to_s
          when Float64 then crystal_type == "Float32" ? "#{raw.to_f32}_f32" : raw.to_s
          end
        end

        private def resolve_base_class(schema : Model::Schema) : String?
          all_of = schema.all_of || return nil
          refs = all_of.select(&.ref?)
          inlines = all_of.reject(&.ref?)
          return nil if refs.size != 1 || inlines.empty?
          TypeMapper.ref_name(refs.first.ref || raise "ref expected")
        end

        private def resolve_composed_from(schema : Model::Schema) : Array(String)?
          all_of = schema.all_of || return nil
          refs = all_of.select(&.ref?)
          return nil unless refs.size > 1
          refs.map { |r| TypeMapper.ref_name(r.ref || raise "ref expected") }
        end

        private def inline_class_name(prop_name : String) : String
          NameInflector.pascal_case(NameInflector.safe_identifier(prop_name))
        end

        private def inline_type(prop_name : String?, or_ref : Model::OrRef(Model::Schema)) : String?
          return nil unless prop_name
          return nil if or_ref.ref?
          schema = or_ref.value || return nil
          nested_name = inline_class_name(prop_name)
          enum_vals = schema.enum_values.try(&.as_a?) || [] of JSON::Any
          if (schema.enum_values && !bool_enum?(enum_vals)) || schema.x_extensible_enum
            nested_name
          elsif (props = schema.properties) && !props.empty?
            nested_name
          elsif schema.type == "array"
            items = schema.items || return nil
            return nil if items.ref?
            item_schema = items.value || return nil
            if item_schema.enum_values || item_schema.x_extensible_enum ||
               ((iprops = item_schema.properties) && !iprops.empty?)
              "Array(#{nested_name})"
            end
          end
        end

        private def emit_inline_classes(
          props : Array(Tuple(String, Model::OrRef(Model::Schema), Bool)),
          b : Crystina::Builder,
        ) : Nil
          props.each do |prop_name, or_ref, _|
            next if or_ref.ref?
            schema = or_ref.value || next
            nested_name = inline_class_name(prop_name)
            ev = schema.enum_values.try(&.as_a?) || [] of JSON::Any
            if schema.enum_values && !bool_enum?(ev)
              emit_enum(nested_name, schema, b)
            elsif schema.x_extensible_enum
              emit_extensible_enum(nested_name, schema, b)
            elsif (object_props = schema.properties) && !object_props.empty?
              emit_nested_class(nested_name, schema, b)
            elsif schema.type == "array"
              if (items = schema.items) && !items.ref?
                if item_schema = items.value
                  iev = item_schema.enum_values.try(&.as_a?) || [] of JSON::Any
                  if item_schema.enum_values && !bool_enum?(iev)
                    emit_enum(nested_name, item_schema, b)
                  elsif item_schema.x_extensible_enum
                    emit_extensible_enum(nested_name, item_schema, b)
                  elsif (iprops = item_schema.properties) && !iprops.empty?
                    emit_nested_class(nested_name, item_schema, b)
                  end
                end
              end
            end
          end
        end

        private def emit_nested_class(name : String, schema : Model::Schema, b : Crystina::Builder) : Nil
          emit_description(schema, b)
          b.scope("class #{name}") { |kb|
            nested_props = collect_properties(schema, nil)
            emit_format_includes(kb, nested_props, has_binary_props?(nested_props))
            kb.blank
            emit_inline_classes(nested_props, kb)
            emit_properties_from_list(nested_props, kb)
            emit_initialize(nested_props, kb)
            emit_validation_methods(nested_props, kb)
          }
          b.blank
        end

        private def has_constraints?(schema : Model::Schema?) : Bool
          return false unless schema
          !schema.minimum.nil? ||
            !schema.maximum.nil? ||
            !schema.min_length.nil? ||
            !schema.max_length.nil? ||
            !schema.pattern.nil? ||
            !schema.min_items.nil? ||
            !schema.max_items.nil? ||
            !schema.multiple_of.nil? ||
            schema.unique_items == true ||
            !schema.min_properties.nil? ||
            !schema.max_properties.nil? ||
            !schema.enum_values.nil?
        end

        private def emit_validation_methods(
          props : Array(Tuple(String, Model::OrRef(Model::Schema), Bool)),
          b : Crystina::Builder,
        ) : Nil
          constrained = props.select { |prop_name, or_ref, _|
            s = or_ref.value || next false
            has_constraints?(s) && !(s.enum_values && inline_type(prop_name, or_ref))
          }
          return if constrained.empty?

          b.blank
          b.def_method("valid?", {} of String => String, "Array(OpenAPI::Validation::Error)") { |mb|
            mb.assign("errors", "[] of OpenAPI::Validation::Error")

            constrained.each do |prop_name, or_ref, _|
              schema = or_ref.value || next
              crystal_prop = @hooks.property_name(prop_name)

              if min_length = schema.min_length
                mb.line("validate_min_length errors, #{prop_name.inspect}, @#{crystal_prop}, #{min_length}")
              end
              if max_length = schema.max_length
                mb.line("validate_max_length errors, #{prop_name.inspect}, @#{crystal_prop}, #{max_length}")
              end
              if pattern = schema.pattern
                safe_pattern = pattern.gsub(/(?<!\\)\//, "\\/")
                mb.line("validate_pattern errors, #{prop_name.inspect}, @#{crystal_prop}, /#{safe_pattern}/, #{pattern.inspect}")
              end
              if minimum = schema.minimum
                min_lit = minimum == minimum.floor ? minimum.to_i64.to_s : minimum.to_s
                excl = schema.exclusive_minimum ? ", true" : ""
                mb.line("validate_minimum errors, #{prop_name.inspect}, @#{crystal_prop}, #{min_lit}#{excl}")
              end
              if maximum = schema.maximum
                max_lit = maximum == maximum.floor ? maximum.to_i64.to_s : maximum.to_s
                excl = schema.exclusive_maximum ? ", true" : ""
                mb.line("validate_maximum errors, #{prop_name.inspect}, @#{crystal_prop}, #{max_lit}#{excl}")
              end
              if min_items = schema.min_items
                mb.line("validate_min_items errors, #{prop_name.inspect}, @#{crystal_prop}, #{min_items}")
              end
              if max_items = schema.max_items
                mb.line("validate_max_items errors, #{prop_name.inspect}, @#{crystal_prop}, #{max_items}")
              end
              if multiple_of = schema.multiple_of
                mo_lit = multiple_of == multiple_of.floor ? multiple_of.to_i64.to_s : multiple_of.to_s
                mb.line("validate_multiple_of errors, #{prop_name.inspect}, @#{crystal_prop}, #{mo_lit}")
              end
              if schema.unique_items
                mb.line("validate_unique_items errors, #{prop_name.inspect}, @#{crystal_prop}")
              end
              if min_properties = schema.min_properties
                mb.line("validate_min_properties errors, #{prop_name.inspect}, @#{crystal_prop}, #{min_properties}")
              end
              if max_properties = schema.max_properties
                mb.line("validate_max_properties errors, #{prop_name.inspect}, @#{crystal_prop}, #{max_properties}")
              end
              if enum_vals = schema.enum_values.try(&.as_a?)
                unless inline_type(prop_name, or_ref)
                  allowed_inspect = enum_vals.map(&.raw.inspect).join(", ")
                  mb.line("validate_enum errors, #{prop_name.inspect}, @#{crystal_prop}, [#{allowed_inspect}]")
                end
              end
            end

            mb.line("errors")
          }
          b.blank
          b.def_method("validate!", {} of String => String, "Nil") { |mb|
            mb.assign("errors", "valid?")
            mb.raise_ex_unless("OpenAPI::Validation::Exception.new(errors)", "errors.empty?")
          }
        end

        private def emit_strip_methods(
          props : Array(Tuple(String, Model::OrRef(Model::Schema), Bool)),
          b : Crystina::Builder,
        ) : Nil
          ro_props = props.select { |_, or_ref, _| or_ref.value.try(&.read_only?) == true }
          wo_props = props.select { |_, or_ref, _| or_ref.value.try(&.write_only?) == true }

          unless ro_props.empty?
            b.blank
            b.comment("Zeroes out read-only fields so client-supplied values are ignored on ingress.")
            b.def_method("strip_read_only!", {} of String => String, "Nil") { |mb|
              ro_props.each { |prop_name, _, _| mb.line("@#{@hooks.property_name(prop_name)} = nil") }
            }
          end

          unless wo_props.empty?
            b.blank
            b.comment("Zeroes out write-only fields so sensitive values are never serialized on egress.")
            b.def_method("strip_write_only!", {} of String => String, "Nil") { |mb|
              wo_props.each { |prop_name, _, _| mb.line("@#{@hooks.property_name(prop_name)} = nil") }
            }
          end
        end
      end
    end
  end
end
