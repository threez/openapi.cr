module OpenAPI
  module Generator
    module Types
      # Extension point for customizing code generation behavior.
      # Subclass `Hooks` and pass your instance to `TypesGenerator.new(hooks)` or
      # `Runner.new(doc, ns, dir, formats, hooks)`.
      #
      # Example — use `BigDecimal` for `number:decimal` fields:
      #   class MyHooks < OpenAPI::Generator::Types::Hooks
      #     def format_type_for(openapi_type, format)
      #       "BigDecimal" if openapi_type == "number" && format == "decimal"
      #     end
      #   end
      abstract class Hooks
        # Return a Crystal type string override for a named top-level schema, or
        # `nil` to use the default mapping.
        # Called when the generator resolves the Crystal type for a named schema
        # (e.g. scalar aliases and array aliases). For property-level scalar
        # overrides use `format_type_for` instead.
        def crystal_type_for(name : String, schema : Model::Schema) : String?
          nil
        end

        # Return a Crystal type string for a given OpenAPI type+format pair,
        # or nil to fall through to the built-in SCALAR_MAP.
        # Use this to add custom format mappings without forking the generator.
        #
        # Example:
        #   def format_type_for(openapi_type, format)
        #     "MyDecimal" if openapi_type == "number" && format == "decimal"
        #   end
        def format_type_for(openapi_type : String, format : String?) : String?
          nil
        end

        # Override the schema kind classification, or nil to use default.
        def classify(name : String, schema : Model::Schema) : SchemaKind?
          nil
        end

        # Whether this named schema should be skipped entirely.
        def skip?(name : String, schema : Model::Schema) : Bool
          false
        end

        # Transform the OpenAPI schema name to a Crystal type identifier.
        def crystal_name(openapi_name : String) : String
          NameInflector.pascal_case(openapi_name)
        end

        # Transform an OpenAPI property name to a Crystal getter name.
        def property_name(openapi_name : String) : String
          NameInflector.safe_identifier(NameInflector.snake_case(openapi_name))
        end

        # Emit additional content after a generated type (e.g. custom methods).
        def after_type(name : String, kind : SchemaKind, b : Crystina::Builder) : Nil
        end
      end

      # The built-in no-op hook implementation used when no custom hooks are provided.
      class DefaultHooks < Hooks
      end
    end
  end
end
