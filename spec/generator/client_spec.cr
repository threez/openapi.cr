require "../spec_helper"

describe OpenAPI::Generator::ClientGenerator do
  it "generates inline validation for operations with constrained parameters" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Petstore", output_path: "/dev/null")
    content = OpenAPI::Generator::ClientGenerator.new.generate(doc, ctx).first.content
    content.should contain("include OpenAPI::Validation::Helpers")
    content.should contain("errors = [] of OpenAPI::Validation::Error")
    content.should contain("validate_maximum errors, \"limit\", limit_val, 100_i32")
    content.should contain("raise OpenAPI::Validation::Exception.new(errors) unless errors.empty?")
    content.should_not contain("def create_pets\ndef create_pets(")
  end

  it "uses add_exploded_param for form+explode=true array params" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::ClientGenerator.new.generate(doc, ctx).first.content
    content.should contain("add_exploded_param(p, \"tags\",")
  end

  it "uses add_joined_param with correct delimiters for non-exploded array params" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::ClientGenerator.new.generate(doc, ctx).first.content
    content.should contain("add_joined_param(p, \"colors\", colors, \",\")")
    content.should contain("add_joined_param(p, \"ids\", ids, \" \")")
    content.should contain("add_joined_param(p, \"codes\", codes, \"|\")")
  end

  it "keeps add_param for scalar query params alongside array params" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::ClientGenerator.new.generate(doc, ctx).first.content
    content.should contain("add_param(p, \"q\",")
  end

  it "omits inline validation when validate_params is false" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Petstore", output_path: "/dev/null", validate_params: false)
    content = OpenAPI::Generator::ClientGenerator.new.generate(doc, ctx).first.content
    content.should_not contain("include OpenAPI::Validation::Helpers")
    content.should_not contain("errors = [] of OpenAPI::Validation::Error")
    content.should_not contain("raise OpenAPI::Validation::Exception")
  end

  it "groups header and cookie request params into named-tuple method args" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::ClientGenerator.new.generate(doc, ctx).first.content
    content.should contain("headers : {x_api_key: String, x_contract_number: Int32?}? = nil")
    content.should contain("cookies : {session_id: String?}? = nil")
  end

  it "sets request headers from named-tuple header params" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::ClientGenerator.new.generate(doc, ctx).first.content
    content.should contain("_req_headers")
    content.should contain("X-Api-Key")
    content.should contain("X-Contract-Number")
  end

  it "returns response-headers tuple when response declares headers" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::ClientGenerator.new.generate(doc, ctx).first.content
    content.should contain("{Resource, {x_request_id: UUID?, x_rate_limit: Int32?}}")
    content.should contain("X-Request-Id")
    content.should contain("X-Rate-Limit")
  end

  it "generates methods for path items defined via $ref" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::ClientGenerator.new.generate(doc, ctx).first.content
    content.should contain("def list_resources")
    content.should contain("/resources")
    content.should contain("/mirror")
  end

  it "inherits path-item-level parameters and overrides them at the operation level" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::ClientGenerator.new.generate(doc, ctx).first.content
    content.should contain("headers : {x_tenant: String?, x_api_key: String}? = nil")
    content.should contain("headers : {x_api_key: String, x_tenant: String}? = nil")
    content.should contain("X-Tenant")
  end

  it "resolves success response as the correct return type" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::ClientGenerator.new.generate(doc, ctx).first.content
    content.should contain("def list_items(")
    content.should contain(") : Array(String)")
  end

  it "emits range case expressions for 4XX and 5XX error responses" do
    doc = OpenAPI::Model::Document.from_file("spec/fixtures/reference.yaml")
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Reference", output_path: "/dev/null")
    content = OpenAPI::Generator::ClientGenerator.new.generate(doc, ctx).first.content
    content.should contain("when 400..499")
    content.should contain("when 500..599")
    content.should contain("ApiError.from_json(response.body)")
  end

  {
    "spec/fixtures/petstore.yaml"       => "Petstore",
    "spec/fixtures/reference.yaml"      => "Reference",
    "spec/fixtures/ionos-nfs-v1.yaml"   => "IonosNfs",
    "spec/fixtures/google-storage.yaml" => "GoogleStorage",
    "spec/fixtures/ionos-cloud-v6.json" => "IonosCloud",
    "spec/fixtures/stripe.json"         => "Stripe",
  }.each do |fixture_path, namespace|
    it "generates client for #{File.basename(fixture_path)}" do
      stem = File.basename(fixture_path, File.extname(fixture_path))
      out_path = "spec/tmp/clients/#{stem}.cr"
      Dir.mkdir_p("spec/tmp/clients")

      doc = OpenAPI::Model::Document.from_file(fixture_path)
      ctx = OpenAPI::Generator::RenderContext.new(namespace: namespace, output_path: out_path)
      files = OpenAPI::Generator::ClientGenerator.new.generate(doc, ctx)

      files.size.should eq(1)
      File.write(out_path, files.first.content)
      files.first.valid_syntax?.should be_true
    end
  end

  it "generates merged client for all seca fixtures" do
    out_path = "spec/tmp/clients/seca.cr"
    Dir.mkdir_p("spec/tmp/clients")
    docs = Dir.glob("spec/fixtures/seca/*.yaml").sort.map { |p| OpenAPI::Model::Document.from_file(p) }
    merged = OpenAPI::Model::Document.merge(docs)
    ctx = OpenAPI::Generator::RenderContext.new(namespace: "Seca", output_path: out_path)
    files = OpenAPI::Generator::ClientGenerator.new.generate(merged, ctx)
    files.size.should eq(1)
    File.write(out_path, files.first.content)
    File.exists?(out_path).should be_true
    files.first.valid_syntax?.should be_true
  end
end
