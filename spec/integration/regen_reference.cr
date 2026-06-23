require "../../src/openapi"

doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
output_dir = "spec/integration/generated/reference"

runner = OpenAPI::Generator::Runner.new(
  doc,
  "Reference",
  output_dir,
  Set{"json", "yaml", "xml", "form", "multipart"},
  OpenAPI::Generator::Types::DefaultHooks.new,
  "spec/fixtures/reference.yaml",
  true,
)

%w[types client server kemal].each do |gen|
  path, content = runner.generate(gen)
  File.write(path, content)
  puts path
end
