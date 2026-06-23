require "../../src/openapi"

doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
formats = Set{"json", "yaml", "xml", "form", "multipart"}

[
  {"spec/tmp/types", OpenAPI::Generator::TypesGenerator.new(OpenAPI::Generator::Types::DefaultHooks.new)},
  {"spec/tmp/clients", OpenAPI::Generator::ClientGenerator.new},
  {"spec/tmp/servers", OpenAPI::Generator::MuxServerGenerator.new},
].each do |(dir, gen)|
  Dir.mkdir_p(dir)
  ctx = OpenAPI::Generator::RenderContext.new(
    namespace: "ReferenceFixture",
    output_path: "#{dir}/reference.cr",
    formats: formats,
    source_file: "spec/fixtures/reference.yaml",
    validate_params: true,
  )
  content = gen.generate(doc, ctx).first.content
  File.write("#{dir}/reference.cr", content)
end
