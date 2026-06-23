module OpenAPI
  module Generator
    # Generates a Crystal source file containing classes, structs, and enums for
    # every schema in an OpenAPI document.
    #
    # ```
    # doc = OpenAPI::Model::Document.from_file("petstore.yaml")
    # ctx = OpenAPI::Generator::RenderContext.new(namespace: "Petstore", output_path: "types.cr")
    # file = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first
    # File.write(file.path, file.content)
    # ```
    class TypesGenerator < Base
      def initialize(@hooks : Types::Hooks = Types::DefaultHooks.new)
      end

      # Runs the generator and returns a single-element array with the generated file.
      def generate(doc : Model::Document, ctx : RenderContext) : Array(GeneratedFile)
        schemas = Types::Collector.collect(doc, @hooks)
        schema_index = schemas.each_with_object({} of String => Model::Schema) { |cs, h| h[cs.name] = cs.schema }
        formats = ctx.formats
        formats |= Set{"form"} if needs_form?(doc)
        formats |= Set{"multipart"} if needs_multipart?(doc)
        # Auto-add or strip XML based entirely on what the doc uses.
        doc_has_xml = needs_xml?(doc)
        formats = doc_has_xml ? formats | Set{"xml"} : formats - Set{"xml"}
        # YAML is needed when the doc has YAML content, or when XML is present
        # (typed_response always has a YAML branch that must compile).
        formats = (needs_yaml?(doc) || doc_has_xml) ? formats | Set{"yaml"} : formats - Set{"yaml"}
        emitter = Types::Emitter.new(@hooks, formats, schema_index, ctx.form_serializer)

        b = Crystina.build
        emit_header(doc, ctx, b)
        emit_requires(schemas, b, formats, ctx.form_serializer)

        if desc = doc.info.description.presence
          desc.each_line { |line| b.comment(line.chomp) }
          b.blank_comment
        end
        b.scope("module #{ctx.namespace}") { |inner|
          version = doc.info.version
          unless version.empty?
            inner.assign("VERSION", version.inspect)
            inner.blank
          end
          schemas.each { |cs| emitter.emit(cs, inner) }
        }

        [GeneratedFile.new(ctx.output_path, b.to_s).format]
      end

      private def needs_yaml?(doc : Model::Document) : Bool
        found = false
        doc.each_path_item do |_, path_item|
          path_item.each_operation do |_, operation|
            req = operation.request_body.try(&.value).try(&.content)
            found = true if req.try(&.any? { |k, _| ParamValidation::YAML_CONTENT_TYPES.includes?(k) })
            operation.responses.each_value do |resp_or_ref|
              content = resp_or_ref.value.try(&.content)
              found = true if content.try(&.any? { |k, _| ParamValidation::YAML_CONTENT_TYPES.includes?(k) })
            end
          end
        end
        found
      end

      private def needs_xml?(doc : Model::Document) : Bool
        found = false
        doc.each_path_item do |_, path_item|
          path_item.each_operation do |_, operation|
            req = operation.request_body.try(&.value).try(&.content)
            found = true if req.try(&.any? { |k, _| ParamValidation::XML_CONTENT_TYPES.includes?(k) })
            operation.responses.each_value do |resp_or_ref|
              content = resp_or_ref.value.try(&.content)
              found = true if content.try(&.any? { |k, _| ParamValidation::XML_CONTENT_TYPES.includes?(k) })
            end
          end
        end
        found
      end

      private def needs_form?(doc : Model::Document) : Bool
        found = false
        doc.each_path_item do |_, path_item|
          path_item.each_operation do |_, operation|
            content = operation.request_body.try(&.value).try(&.content)
            found = true if content.try(&.has_key?("application/x-www-form-urlencoded"))
          end
        end
        found
      end

      private def needs_multipart?(doc : Model::Document) : Bool
        found = false
        doc.each_path_item do |_, path_item|
          path_item.each_operation do |_, operation|
            content = operation.request_body.try(&.value).try(&.content)
            found = true if content.try(&.has_key?(ParamValidation::MULTIPART_CONTENT_TYPE))
          end
        end
        found
      end

      private def emit_requires(schemas : Array(Types::ClassifiedSchema), b : Crystina::Builder, formats : Set(String), form_serializer : String = "OpenAPI::Form::Serializable") : Nil
        b.req("json") if formats.includes?("json")
        b.req("yaml") if formats.includes?("yaml")
        b.req("openapi/xml/serializable") if formats.includes?("xml")
        b.req("openapi/form/serializable") if formats.includes?("form") && form_serializer == "OpenAPI::Form::Serializable"
        b.req("openapi/multipart/serializable") if formats.includes?("multipart")

        if needs_format?(schemas, "uuid")
          b.req("uuid")
          b.req("uuid/json") if formats.includes?("json")
          b.req("uuid/yaml") if formats.includes?("yaml")
        end
        if needs_format?(schemas, "uri")
          b.req("uri")
          b.req("uri/json") if formats.includes?("json")
          b.req("uri/yaml") if formats.includes?("yaml")
        end
        b.req("openapi/converter/base64") if needs_format?(schemas, "byte") && formats.includes?("json")
        b.req("openapi/macro/enum") if needs_enum_macro?(schemas)
        b.req("openapi/macro/union") if needs_union_macro?(schemas)
        b.req("openapi/macro/allof") if needs_allof_macro?(schemas)
        b.req("openapi/macro/exception") if needs_exception_macro?(schemas)
        b.req("openapi/validation/error") if needs_validation?(schemas)
        b.req("openapi/validation/helpers") if needs_validation?(schemas)

        b.blank
      end

      private def needs_format?(schemas : Array(Types::ClassifiedSchema), format : String) : Bool
        schemas.any? { |cs| schema_uses_format?(cs.schema, format) }
      end

      private def schema_uses_format?(schema : Model::Schema, format : String) : Bool
        return true if schema.format == format
        if props = schema.properties
          return true if props.any? { |_, r| r.value.try { |s| schema_uses_format?(s, format) } }
        end
        if all_of = schema.all_of
          return true if all_of.any? { |r| r.value.try { |s| schema_uses_format?(s, format) } }
        end
        false
      end

      private def needs_union_macro?(schemas : Array(Types::ClassifiedSchema)) : Bool
        schemas.any? { |cs| cs.kind.union_alias? || cs.kind.abstract_class? }
      end

      private def needs_exception_macro?(schemas : Array(Types::ClassifiedSchema)) : Bool
        schemas.any? { |cs| cs.source.error? && (cs.kind.class? || cs.kind.struct?) }
      end

      private def needs_allof_macro?(schemas : Array(Types::ClassifiedSchema)) : Bool
        schemas.any?(&.kind.compose_alias?)
      end

      private def needs_enum_macro?(schemas : Array(Types::ClassifiedSchema)) : Bool
        schemas.any?(&.kind.enum?) ||
          schemas.any?(&.kind.extensible_enum?) ||
          schemas.any? do |cs|
            next false unless cs.kind.struct? || cs.kind.class?
            props = cs.schema.properties || next false
            props.any? do |_, r|
              s = r.value || next false
              next true if s.enum_values || s.x_extensible_enum
              if s.type == "array"
                items = s.items || next false
                next false if items.ref?
                item_s = items.value || next false
                !item_s.enum_values.nil? || !item_s.x_extensible_enum.nil?
              else
                false
              end
            end
          end
      end

      private def needs_validation?(schemas : Array(Types::ClassifiedSchema)) : Bool
        schemas.any? do |cs|
          next false unless cs.kind.struct? || cs.kind.class?
          props = cs.schema.properties
          next false unless props
          props.any? do |_, or_ref|
            s = or_ref.value
            next false unless s
            !s.minimum.nil? || !s.maximum.nil? ||
              !s.min_length.nil? || !s.max_length.nil? ||
              !s.pattern.nil? || !s.min_items.nil? ||
              !s.max_items.nil?
          end
        end
      end
    end
  end
end
