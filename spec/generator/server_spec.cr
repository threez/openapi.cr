require "../spec_helper"

describe OpenAPI::Generator::ServerGenerator do
  it "generates abstract class Handler for petstore" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Petstore", output_path: "/dev/null")
    content = OpenAPI::Generator::MuxServerGenerator.new.generate(doc, ctx).first.content
    content.should contain("abstract class Handler")
    content.should contain("def register(mux : Mux::Router)")
  end

  it "generates abstract defs with typed signatures" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Petstore", output_path: "/dev/null")
    content = OpenAPI::Generator::MuxServerGenerator.new.generate(doc, ctx).first.content
    content.should contain("abstract def list_pets(")
    content.should contain("abstract def show_pet_by_id(")
  end

  it "converts OpenAPI path params to mux.cr colon syntax" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Petstore", output_path: "/dev/null")
    content = OpenAPI::Generator::MuxServerGenerator.new.generate(doc, ctx).first.content
    content.should contain("/pets/:petId")
    content.should_not contain("/pets/{petId}")
  end

  it "wraps route handlers in begin/rescue with typed and generic clauses" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Petstore", output_path: "/dev/null")
    content = OpenAPI::Generator::MuxServerGenerator.new.generate(doc, ctx).first.content
    content.should contain("rescue ex : Error")
    content.should contain("rescue ex : Exception")
    content.should contain("json_error ctx, ex,")
    content.should contain("ex.message")
  end

  it "generates abstract defs and routes for path items defined via $ref" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::MuxServerGenerator.new.generate(doc, ctx).first.content
    content.should contain("abstract def list_resources")
    content.should contain("/resources")
    content.should contain("/mirror")
  end

  it "emits query param parsing in route handler" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Petstore", output_path: "/dev/null")
    content = OpenAPI::Generator::MuxServerGenerator.new.generate(doc, ctx).first.content
    content.should contain("query_int32(ctx, \"limit\")")
  end

  it "generates validate_params helpers for operations with constrained parameters" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Petstore", output_path: "/dev/null")
    content = OpenAPI::Generator::MuxServerGenerator.new.generate(doc, ctx).first.content
    content.should contain("include OpenAPI::Validation::Helpers")
    content.should contain("# Validates the constrained parameters for `list_pets`")
    content.should contain("# * `limit` — maximum: 100")
    content.should contain("def validate_list_pets_params(")
    content.should contain("validate_maximum errors, \"limit\", limit_val, 100_i32")
    content.should_not contain("def validate_create_pets_params(")
    content.should_not contain("def validate_show_pet_by_id_params(")
  end

  it "groups header and cookie request params into named-tuple args in abstract def" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::MuxServerGenerator.new.generate(doc, ctx).first.content
    content.should contain("headers : {x_api_key: String, x_contract_number: Int32?}? = nil")
    content.should contain("cookies : {session_id: String?}? = nil")
  end

  it "extracts header params and builds named tuple in route handler" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::MuxServerGenerator.new.generate(doc, ctx).first.content
    content.should contain("header_string(ctx, \"X-Api-Key\")")
    content.should contain("header_int32(ctx, \"X-Contract-Number\")")
    content.should contain("_req_headers")
  end

  it "emits response header tuple handling when response declares headers" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::MuxServerGenerator.new.generate(doc, ctx).first.content
    content.should contain("{Resource, {x_request_id: UUID?, x_rate_limit: Int32?}}")
    content.should contain("_result_tuple")
    content.should contain("X-Request-Id")
    content.should contain("X-Rate-Limit")
  end

  it "merges path-item-level parameters and lets operation-level params override" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::MuxServerGenerator.new.generate(doc, ctx).first.content
    content.should contain("headers : {x_tenant: String?, x_api_key: String}? = nil,")
    content.should contain("headers : {x_api_key: String, x_tenant: String}? = nil,")
    content.should contain("path_uuid(ctx, :id)")
    content.should contain("header_string(ctx, \"X-Tenant\")")
  end

  it "resolves success response as the correct return type and uses status 200" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::MuxServerGenerator.new.generate(doc, ctx).first.content
    content.should contain("abstract def list_items(")
    content.should contain(") : Array(String)")
    content.should contain("json_response ctx, 200,")
  end

  it "maps 4XX and 5XX range responses to representative status codes in rescue clauses" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::MuxServerGenerator.new.generate(doc, ctx).first.content
    content.should contain("rescue ex : ApiError")
    content.should contain("json_error ctx, ex, 400")
  end

  {
    "spec/fixtures/petstore.yaml"       => "Petstore",
    "spec/fixtures/reference.yaml"      => "Reference",
    "spec/fixtures/ionos-nfs-v1.yaml"   => "IonosNfs",
    "spec/fixtures/google-storage.yaml" => "GoogleStorage",
    "spec/fixtures/ionos-cloud-v6.json" => "IonosCloud",
    "spec/fixtures/stripe.json"         => "Stripe",
  }.each do |fixture_path, namespace|
    it "generates server for #{File.basename(fixture_path)}" do
      stem = File.basename(fixture_path, File.extname(fixture_path))
      out_path = "spec/tmp/servers/#{stem}.cr"
      Dir.mkdir_p("spec/tmp/servers")

      doc = OpenAPI::Model::Document.from_file(fixture_path)
      ctx = OpenAPI::Generator::RenderContext.new(namespace: namespace, output_path: out_path)
      files = OpenAPI::Generator::MuxServerGenerator.new.generate(doc, ctx)

      files.size.should eq(1)
      File.write(out_path, files.first.content)
      files.first.content.should contain("abstract class Handler")
      files.first.content.should contain("def register(mux : Mux::Router)")
      files.first.valid_syntax?.should be_true
    end
  end

  it "generates merged server for all seca fixtures" do
    out_path = "spec/tmp/servers/seca.cr"
    Dir.mkdir_p("spec/tmp/servers")
    docs = Dir.glob("spec/fixtures/seca/*.yaml").sort.map { |p| OpenAPI::Model::Document.from_file(p) }
    merged = OpenAPI::Model::Document.merge(docs)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Seca", output_path: out_path)
    files = OpenAPI::Generator::MuxServerGenerator.new.generate(merged, ctx)
    files.size.should eq(1)
    File.write(out_path, files.first.content)
    files.first.content.should contain("abstract class Handler")
    files.first.valid_syntax?.should be_true
  end
end

describe "integration fixture golden files" do
  tmp_dir = "spec/tmp/integration"

  # Skip the file header (Generated by + Source + blank line) before comparing;
  # PROGRAM_NAME in the header changes across different binary builds.
  strip_header = ->(content : String) {
    idx = content.index("\n\n")
    idx ? content[(idx + 2)..] : content
  }

  it "types fixture matches generated output" do
    Dir.mkdir_p(tmp_dir)
    out_path = "#{tmp_dir}/types.cr"
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Petstore", output_path: out_path)
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    File.write(out_path, content)
    strip_header.call(content).should eq(strip_header.call(File.read("spec/integration/generated/types.cr")))
  end

  it "client fixture matches generated output" do
    Dir.mkdir_p(tmp_dir)
    out_path = "#{tmp_dir}/client.cr"
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Petstore", output_path: out_path)
    content = OpenAPI::Generator::ClientGenerator.new.generate(doc, ctx).first.content
    File.write(out_path, content)
    strip_header.call(content).should eq(strip_header.call(File.read("spec/integration/generated/client.cr")))
  end

  it "server fixture matches generated output" do
    Dir.mkdir_p(tmp_dir)
    out_path = "#{tmp_dir}/server.cr"
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Petstore", output_path: out_path)
    content = OpenAPI::Generator::MuxServerGenerator.new.generate(doc, ctx).first.content
    File.write(out_path, content)
    strip_header.call(content).should eq(strip_header.call(File.read("spec/integration/generated/server.cr")))
  end

  it "kemal_server fixture matches generated output" do
    Dir.mkdir_p(tmp_dir)
    out_path = "#{tmp_dir}/kemal_server.cr"
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Petstore", output_path: out_path)
    content = OpenAPI::Generator::KemalServerGenerator.new.generate(doc, ctx).first.content
    File.write(out_path, content)
    strip_header.call(content).should eq(strip_header.call(File.read("spec/integration/generated/kemal_server.cr")))
  end

  it "reference types fixture matches generated output" do
    Dir.mkdir_p("#{tmp_dir}/reference")
    out_path = "#{tmp_dir}/reference/types.cr"
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: out_path)
    content = OpenAPI::Generator::TypesGenerator.new.generate(doc, ctx).first.content
    File.write(out_path, content)
    strip_header.call(content).should eq(strip_header.call(File.read("spec/integration/generated/reference/types.cr")))
  end

  it "reference client fixture matches generated output" do
    Dir.mkdir_p("#{tmp_dir}/reference")
    out_path = "#{tmp_dir}/reference/client.cr"
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: out_path)
    content = OpenAPI::Generator::ClientGenerator.new.generate(doc, ctx).first.content
    File.write(out_path, content)
    strip_header.call(content).should eq(strip_header.call(File.read("spec/integration/generated/reference/client.cr")))
  end

  it "reference server fixture matches generated output" do
    Dir.mkdir_p("#{tmp_dir}/reference")
    out_path = "#{tmp_dir}/reference/server.cr"
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: out_path)
    content = OpenAPI::Generator::MuxServerGenerator.new.generate(doc, ctx).first.content
    File.write(out_path, content)
    strip_header.call(content).should eq(strip_header.call(File.read("spec/integration/generated/reference/server.cr")))
  end

  it "reference kemal_server fixture matches generated output" do
    Dir.mkdir_p("#{tmp_dir}/reference")
    out_path = "#{tmp_dir}/reference/kemal_server.cr"
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: out_path)
    content = OpenAPI::Generator::KemalServerGenerator.new.generate(doc, ctx).first.content
    File.write(out_path, content)
    strip_header.call(content).should eq(strip_header.call(File.read("spec/integration/generated/reference/kemal_server.cr")))
  end
end
