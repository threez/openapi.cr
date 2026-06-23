module OpenAPI
  module Generator
    # Orchestrates multiple generators from a single OpenAPI document.
    # Prefer this over calling generators individually when writing to disk.
    #
    # ```
    # doc = OpenAPI::Model::Document.from_file("petstore.yaml")
    # runner = OpenAPI::Generator::Runner.new(doc, "Petstore", "src/generated")
    # runner.run(%w[types client server]).each do |(path, content)|
    #   File.write(path, content)
    # end
    # ```
    class Runner
      # Names of all built-in generators: `types`, `client`, `server`, `kemal`.
      GENERATORS = %w[types client server kemal]

      # Creates a runner.
      #
      # - *doc* — parsed OpenAPI document to generate from.
      # - *namespace* — top-level Crystal module name (e.g. `"Petstore"`).
      # - *output_dir* — directory where generated files will be written.
      # - *formats* — serialization formats to emit (`"json"`, `"yaml"`, `"xml"`).
      # - *hooks* — custom type-generation hooks; defaults to `Types::DefaultHooks`.
      # - *source_file* — optional path written as a `# source:` comment in generated files.
      # - *validate_params* — when `true`, generated server helpers validate operation parameters.
      # - *form_serializer* — fully-qualified Crystal module included on form-encoded request body types.
      #   Defaults to `OpenAPI::Form::Serializable`. Override to substitute a custom encoding module.
      def initialize(
        @doc : Model::Document,
        @namespace : String,
        @output_dir : String,
        @formats : Set(String) = Set{"json", "yaml"},
        @hooks : Types::Hooks = Types::DefaultHooks.new,
        @source_file : String? = nil,
        @validate_params : Bool = true,
        @form_serializer : String = "OpenAPI::Form::Serializable",
      )
      end

      # Runs each named generator and returns their `{output_path, content}` pairs.
      def run(generators : Array(String)) : Array({String, String})
        generators.map { |name| generate(name) }
      end

      # Runs a single named generator and returns `{output_path, content}`.
      # Raises `ArgumentError` for unknown generator names.
      def generate(name : String) : {String, String}
        case name
        when "types"
          path = File.join(@output_dir, "types.cr")
          {path, TypesGenerator.new(@hooks).generate(@doc, ctx(path)).first.content}
        when "client"
          path = File.join(@output_dir, "client.cr")
          {path, ClientGenerator.new.generate(@doc, ctx(path)).first.content}
        when "server"
          path = File.join(@output_dir, "server.cr")
          {path, MuxServerGenerator.new.generate(@doc, ctx(path)).first.content}
        when "kemal"
          path = File.join(@output_dir, "kemal_server.cr")
          {path, KemalServerGenerator.new.generate(@doc, ctx(path)).first.content}
        else
          raise ArgumentError.new("unknown generator '#{name}' (valid: #{GENERATORS.join(", ")})")
        end
      end

      private def ctx(output_path : String) : RenderContext
        RenderContext.new(namespace: @namespace, output_path: output_path, formats: @formats, source_file: @source_file, validate_params: @validate_params, form_serializer: @form_serializer)
      end
    end
  end
end
