module OpenAPI
  module Generator
    module Types
      # :nodoc:
      enum SchemaSource
        Components
        Request
        Response
        Error
        Parameter
      end

      # :nodoc:
      record ClassifiedSchema,
        name : String,
        schema : Model::Schema,
        kind : SchemaKind,
        source : SchemaSource
    end
  end
end
