module OpenAPI
  module Generator
    module Types
      # :nodoc:
      module Collector
        KIND_ORDER = {
          SchemaKind::ScalarAlias    => 0,
          SchemaKind::Enum           => 1,
          SchemaKind::ExtensibleEnum => 2,
          SchemaKind::ArrayAlias     => 3,
          SchemaKind::Struct         => 4,
          SchemaKind::Class          => 5,
          SchemaKind::AbstractClass  => 6,
          SchemaKind::AnyAlias       => 7,
          SchemaKind::UnionAlias     => 8,
          SchemaKind::ComposeAlias   => 9,
          SchemaKind::Skip           => 10,
          SchemaKind::ErrorWrapper   => 11,
        }

        def self.collect(doc : Model::Document, hooks : Hooks) : Array(ClassifiedSchema)
          results = [] of ClassifiedSchema

          error_ref_names = Set(String).new
          error_response_wrappers = {} of String => String

          doc.each_path_item do |_, path_item|
            path_item.each_operation do |_, operation|
              operation.responses.each do |status_key, resp_or_ref|
                next if status_key.starts_with?("2")
                if resp_ref = resp_or_ref.ref
                  comp_name = resp_ref.split("/").last
                  response = doc.components.try(&.responses.try(&.[comp_name]?)).try(&.value) || next
                  content = response.content || next
                  schema_or_ref = content[pick_content_key(content) || ""]?.try(&.schema) || next
                  if parent_ref = schema_or_ref.ref
                    error_response_wrappers[comp_name] = parent_ref
                    error_ref_names << TypeMapper.ref_name(parent_ref)
                  end
                else
                  response = resp_or_ref.value || next
                  content = response.content || next
                  schema_or_ref = content[pick_content_key(content) || ""]?.try(&.schema) || next
                  if ref = schema_or_ref.ref
                    error_ref_names << TypeMapper.ref_name(ref)
                  end
                end
              end
            end
          end

          doc.components.try(&.schemas.try(&.each do |name, or_ref|
            schema = or_ref.value || next
            next if hooks.skip?(name, schema)
            kind = classify(name, schema, hooks)
            next if kind.skip?
            source = error_ref_names.includes?(hooks.crystal_name(name)) ? SchemaSource::Error : SchemaSource::Components
            results << ClassifiedSchema.new(name, schema, kind, source)
          end))

          seen = results.map(&.name).to_set

          error_response_wrappers.each do |name, parent_ref|
            next if seen.includes?(name)
            schema = Model::Schema.from_json(%({"allOf":[{"$ref":#{parent_ref.to_json}}]}))
            next if hooks.skip?(name, schema)
            results << ClassifiedSchema.new(name, schema, SchemaKind::ErrorWrapper, SchemaSource::Error)
            seen << name
          end

          doc.each_path_item do |path_template, path_item|
            path_item.each_operation do |http_method, operation|
              if rb_schema = inline_object_schema(
                   operation.request_body.try(&.value).try(&.content).try { |c|
                     c[pick_content_key(c) || ""]?.try(&.schema)
                   })
                name = NameInflector.operation_type_name(
                  operation.operation_id, http_method, path_template) + "Request"
                unless seen.includes?(name) || hooks.skip?(name, rb_schema)
                  kind = classify(name, rb_schema, hooks)
                  unless kind.skip?
                    results << ClassifiedSchema.new(name, rb_schema, kind, SchemaSource::Request)
                    seen << name
                  end
                end
              end

              if resp_schema = inline_object_schema(success_response_schema(operation))
                name = NameInflector.operation_type_name(
                  operation.operation_id, http_method, path_template) + "Response"
                unless seen.includes?(name) || hooks.skip?(name, resp_schema)
                  kind = classify(name, resp_schema, hooks)
                  unless kind.skip?
                    results << ClassifiedSchema.new(name, resp_schema, kind, SchemaSource::Response)
                    seen << name
                  end
                end
              end

              operation.responses.each do |status_key, resp_or_ref|
                next if status_key.starts_with?("2")
                response = resolve_response(doc, resp_or_ref) || next
                content = response.content || next
                schema_or_ref = content[pick_content_key(content) || ""]?.try(&.schema) || next
                err_schema = inline_object_schema(schema_or_ref) || next
                name = NameInflector.operation_error_type_name(
                  operation.operation_id, http_method, path_template, status_key)
                unless seen.includes?(name) || hooks.skip?(name, err_schema)
                  kind = classify(name, err_schema, hooks)
                  kind = SchemaKind::Class if kind.struct?
                  unless kind.skip?
                    results << ClassifiedSchema.new(name, err_schema, kind, SchemaSource::Error)
                    seen << name
                  end
                end
              end
            end
          end

          doc.each_path_item do |_, path_item|
            path_item.each_operation do |_, operation|
              merge_parameters(doc, path_item.parameters, operation.parameters).each do |param|
                schema_or = param.schema || next
                next if schema_or.ref?
                schema = schema_or.value || next
                next unless TypeMapper.string_enum?(schema)
                name = NameInflector.pascal_case(NameInflector.safe_identifier(param.name))
                next if seen.includes?(name) || hooks.skip?(name, schema)
                results << ClassifiedSchema.new(name, schema, SchemaKind::Enum, SchemaSource::Parameter)
                seen << name
              end
            end
          end

          results.sort_by { |cs| {KIND_ORDER[cs.kind], cs.name} }
        end

        private def self.classify(name : String, schema : Model::Schema, hooks : Hooks) : SchemaKind
          if kind = hooks.classify(name, schema)
            return kind
          end

          return SchemaKind::Enum if schema.enum_values
          return SchemaKind::ExtensibleEnum if schema.x_extensible_enum

          return SchemaKind::ArrayAlias if schema.type == "array"

          # Pure scalar type (no object structure, no composition)
          if TypeMapper.scalar?(schema) &&
             schema.properties.nil? &&
             schema.all_of.nil? &&
             schema.one_of.nil? &&
             schema.any_of.nil?
            return SchemaKind::ScalarAlias
          end

          if all_of = schema.all_of
            refs = all_of.select(&.ref?)
            inlines = all_of.reject(&.ref?)
            # Single $ref with no other additions → alias
            return SchemaKind::ScalarAlias if refs.size == 1 && inlines.empty? && schema.properties.nil?
            # All $refs (2+), no inline entries, no extra properties → delegate wrapper struct
            return SchemaKind::ComposeAlias if refs.size > 1 && inlines.empty? && schema.properties.nil?
            # Everything else (inheritance or composition with extras) → Class
            return SchemaKind::Class
          end

          if schema.one_of || schema.any_of
            return SchemaKind::AbstractClass if schema.discriminator
            if variants = schema.one_of || schema.any_of
              all_refs = variants.all?(&.ref)
              return SchemaKind::ScalarAlias if all_refs && variants.size == 1
              return SchemaKind::UnionAlias if all_refs && variants.size > 1
              return SchemaKind::AnyAlias
            end
          end

          # Pure additionalProperties map (no regular properties) → Hash alias
          if TypeMapper.additional_properties_hash_type(schema)
            return SchemaKind::ArrayAlias
          end

          if schema.type == "object" || schema.properties
            return use_struct?(schema) ? SchemaKind::Struct : SchemaKind::Class
          end

          # Empty or unrecognized schema → JSON::Any alias
          SchemaKind::AnyAlias
        end

        private def self.inline_object_schema(or_ref : Model::OrRef(Model::Schema)?) : Model::Schema?
          return nil unless or_ref
          return nil if or_ref.ref
          s = or_ref.value || return nil
          return nil unless s.type == "object" && s.properties
          s
        end

        # Returns the content-map key to use for schema resolution.
        # Prefers application/json > text/json > application/yaml > text/yaml >
        # application/x-yaml > text/x-yaml > application/x-www-form-urlencoded > first key.
        private def self.pick_content_key(content : Hash(String, Model::MediaType)) : String?
          ParamValidation::JSON_CONTENT_TYPES.each { |k| return k if content.has_key?(k) }
          ParamValidation::YAML_CONTENT_TYPES.each { |k| return k if content.has_key?(k) }
          return "application/x-www-form-urlencoded" if content.has_key?("application/x-www-form-urlencoded")
          content.first_key?
        end

        private def self.success_response_schema(operation : Model::Operation) : Model::OrRef(Model::Schema)?
          resp_or_ref =
            operation.responses["200"]? ||
              operation.responses["201"]? ||
              operation.responses.find { |k, _| k.starts_with?("2") }.try(&.last)
          return nil unless resp_or_ref
          response = resp_or_ref.value || return nil
          content = response.content || return nil
          content[pick_content_key(content) || ""]?.try(&.schema)
        end

        private def self.parameter_schema(p : Model::Parameter) : Model::OrRef(Model::Schema)?
          p.schema || p.content.try { |c| c[pick_content_key(c) || ""]?.try(&.schema) }
        end

        private def self.merge_parameters(
          doc : Model::Document,
          path_params : Array(Model::OrRef(Model::Parameter))?,
          op_params : Array(Model::OrRef(Model::Parameter))?,
        ) : Array(Model::Parameter)
          base = (path_params || [] of Model::OrRef(Model::Parameter)).compact_map { |or_ref| resolve_parameter(doc, or_ref) }
          over = (op_params || [] of Model::OrRef(Model::Parameter)).compact_map { |or_ref| resolve_parameter(doc, or_ref) }
          overridden = over.map { |p| {p.name, p.location} }.to_set
          base.reject { |p| overridden.includes?({p.name, p.location}) } + over
        end

        private def self.resolve_parameter(doc : Model::Document, or_ref : Model::OrRef(Model::Parameter)) : Model::Parameter?
          or_ref.value || or_ref.ref.try { |r|
            doc.components.try(&.parameters).try(&.[r.split("/").last]?).try(&.value)
          }
        end

        private def self.resolve_response(
          doc : Model::Document,
          or_ref : Model::OrRef(Model::Response),
        ) : Model::Response?
          or_ref.value || or_ref.ref.try { |r|
            doc.components.try(&.responses.try(&.[r.split("/").last]?)).try(&.value)
          }
        end

        private def self.use_struct?(schema : Model::Schema) : Bool
          return false if schema.all_of || schema.one_of || schema.any_of

          props = schema.properties
          return false if !props || props.empty? || props.size > 6

          req_set = (schema.required || [] of String).to_set
          return false unless props.keys.all? { |k| req_set.includes?(k) }

          props.all? do |_, or_ref|
            if or_ref.ref?
              true
            elsif s = or_ref.value
              TypeMapper.scalar?(s) || s.type == "array"
            else
              false
            end
          end
        end
      end
    end
  end
end
