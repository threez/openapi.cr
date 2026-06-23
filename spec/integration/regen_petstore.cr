require "../../src/openapi"

doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
output_dir = "spec/integration/generated"

runner = OpenAPI::Generator::Runner.new(
  doc,
  "Petstore",
  output_dir,
  Set{"json", "xml"},
  OpenAPI::Generator::Types::DefaultHooks.new,
  "spec/fixtures/petstore.yaml",
  true,
)

%w[types client server kemal].each do |gen|
  path, content = runner.generate(gen)
  File.write(path, content)
  puts path
end
