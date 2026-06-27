require "option_parser"
require "./macro/enum"
require "./validation/error"
require "./model"
require "./generator"

module OpenAPI
  module CLI
    # :nodoc:
    DEFAULT_GENERATORS = %w[types client server]

    private class CLIHooks < Generator::Types::DefaultHooks
      def initialize(@custom_scalars : Hash({String, String?}, String))
      end

      def format_type_for(openapi_type : String, format : String?) : String?
        @custom_scalars[{openapi_type, format}]?
      end
    end

    # Entry point for the `cryogen` CLI tool. Returns 0 on success, 1 on error.
    def self.run(args : Array(String)) : Int32
      spec_files = [] of String
      namespace = nil
      output_dir = "."
      generators = DEFAULT_GENERATORS.dup
      formats = Set{"json", "yaml"}
      custom_scalars = {} of {String, String?} => String
      validate_params = true
      form_serializer = "OpenAPI::Form::Serializable"

      parser = OptionParser.new do |p|
        p.banner = <<-BANNER
          cryogen — Crystal code generator for OpenAPI 3.x specs

          Usage:
            cryogen [options] <spec-file>

          Examples:
            cryogen petstore.yaml
            cryogen petstore.yaml --namespace MyApi --output src/generated
            cryogen petstore.yaml --generators types,client
            cryogen petstore.yaml --formats json
            cryogen petstore.yaml --custom-scalar string:ipv4=IPv4 --custom-scalar string:ipv6=IPv6

          Options:
          BANNER
        p.on("--namespace NAME", "Crystal module namespace (default: derived from filename)") { |v| namespace = v }
        p.separator "      Wraps all generated code. Defaults to the spec filename in PascalCase."
        p.separator "      Example: petstore.yaml → Petstore"
        p.separator ""
        p.on("--output DIR", "Output directory (default: .)") { |v| output_dir = v }
        p.separator "      Created automatically if it does not exist."
        p.separator ""
        p.on("--generators LIST", "Generators to run (default: types,client,server)") { |v| generators = v.split(",") }
        p.separator "      types   — Crystal classes/structs/enums for all schemas"
        p.separator "      client  — HTTP client with a typed method per operation"
        p.separator "      server  — Abstract handler for the Mux router"
        p.separator "      kemal   — Abstract handler for the Kemal framework"
        p.separator "      Available: #{Generator::Runner::GENERATORS.join(", ")}"
        p.separator ""
        p.on("--formats LIST", "Serialization formats to emit (default: json,yaml)") { |v| formats = v.split(",").to_set }
        p.separator "      json  — adds JSON::Serializable to every type"
        p.separator "      yaml  — adds YAML::Serializable to every type"
        p.separator ""
        p.on("--custom-scalar MAPPING", "Override a scalar type mapping (repeatable)") do |v|
          key, crystal_type = v.split("=", 2)
          parts = key.split(":", 2)
          custom_scalars[{parts[0], parts[1]?}] = crystal_type
        end
        p.separator "      Format:  <openapi-type>:<format>=<CrystalType>"
        p.separator "      Omit :<format> to match any format for that type."
        p.separator "      Examples: --custom-scalar string:ipv4=IPv4"
        p.separator "                --custom-scalar string:decimal=BigDecimal"
        p.separator "                --custom-scalar number=Float32"
        p.separator ""
        p.on("--no-validate-params", "Disable client-side parameter validation") { validate_params = false }
        p.separator "      When set, the generated client will not validate constrained parameters"
        p.separator "      before sending the HTTP request."
        p.separator ""
        p.on("--form-serializer MODULE", "Custom form serializer module (default: OpenAPI::Form::Serializable)") { |v| form_serializer = v }
        p.separator "      Replaces OpenAPI::Form::Serializable in the include line of generated"
        p.separator "      request-body types that use application/x-www-form-urlencoded."
        p.separator "      The module must expose to_form_params : String and"
        p.separator "      self.from_form_params(params : HTTP::Params, prefix : String? = nil) : self."
        p.separator ""
        p.on("-h", "--help", "Show this help") { puts p; exit 0 }
        p.unknown_args { |rest, _| spec_files.concat(rest) }
        p.invalid_option { |flag| STDERR.puts "Unknown option: #{flag}"; STDERR.puts p; exit 1 }
      end
      parser.parse(args)

      if spec_files.empty?
        STDERR.puts "Error: spec file required"
        STDERR.puts parser
        return 1
      end

      spec_files.each do |f|
        unless File.exists?(f)
          STDERR.puts "Error: file not found: #{f}"
          return 1
        end
      end

      if spec_files.size > 1 && namespace.nil?
        STDERR.puts "Error: --namespace required when merging multiple files"
        return 1
      end

      _ns = namespace
      ns = _ns || derive_namespace(spec_files.first)
      docs = spec_files.map { |f| Model::Document.from_file(f) }
      doc = docs.size == 1 ? docs.first : Model::Document.merge(docs)
      Dir.mkdir_p(output_dir)

      hooks = CLIHooks.new(custom_scalars)
      source_file = spec_files.size == 1 ? spec_files.first : nil
      runner = Generator::Runner.new(doc, ns, output_dir, formats, hooks, source_file, validate_params, form_serializer)

      generators.each do |gen|
        path, content = runner.generate(gen)
        File.write(path, content)
        puts path
      rescue ex : ArgumentError
        STDERR.puts "Error: #{ex.message}"
        return 1
      end

      0
    end

    private def self.derive_namespace(spec_file : String) : String
      stem = File.basename(spec_file, File.extname(spec_file))
      Generator::Types::NameInflector.pascal_case(stem)
    end
  end
end

exit OpenAPI::CLI.run(ARGV)
