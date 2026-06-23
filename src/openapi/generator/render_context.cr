module OpenAPI
  module Generator
    # Configuration for a generator run: the Crystal module namespace, output file
    # path, the set of serialization formats to include (`"json"`, `"yaml"`),
    # and an optional source file path shown in the generated file header.
    class RenderContext
      getter namespace : String
      getter output_path : String
      getter formats : Set(String)
      getter source_file : String?
      getter validate_params : Bool # ameba:disable Naming/QueryBoolMethods
      getter form_serializer : String

      def initialize(
        @namespace : String,
        @output_path : String,
        @formats : Set(String) = Set{"json", "yaml"},
        @source_file : String? = nil,
        @validate_params : Bool = true,
        @form_serializer : String = "OpenAPI::Form::Serializable",
      )
      end
    end
  end
end
