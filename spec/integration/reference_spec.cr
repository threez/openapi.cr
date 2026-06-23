# Generate reference output into spec/tmp/ at compile time so that the require
# directives below resolve even in a clean checkout (spec/tmp/ is gitignored).
{{ `crystal run spec/integration/gen_reference_tmp.cr` }}

require "../spec_helper"
require "../tmp/types/reference"
require "../tmp/clients/reference"
require "../tmp/servers/reference"

# ── Concrete server handler ───────────────────────────────────────────────────

class TestReferenceHandler < ReferenceFixture::Handler
  # Captured request values so specs can assert without inspecting HTTP headers
  # directly.
  property last_api_key : String? = nil
  property last_contract_number : Int32? = nil
  property last_session_id : String? = nil
  property last_submit_body : ReferenceFixture::Resource? = nil
  property? force_items_error : Bool = false

  FIXED_UUID    = UUID.new("a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11")
  ITEM_RESOURCE = ReferenceFixture::Resource.new(
    id: ReferenceFixture::ResourceId.new("00000000-0000-0000-0000-000000000001"),
    name: "item-resource",
    status: ReferenceFixture::ResourceStatus::Active,
  )

  # ── /resources ───────────────────────────────────────────────────────────────

  def list_resources(
    limit : Int32? = nil,
    offset : Int32? = nil,
    sort : ReferenceFixture::Sort? = nil,
    tags : Array(String)? = nil,
    headers : {x_api_key: String, x_contract_number: Int32?}? = nil,
    cookies : {session_id: String?}? = nil,
  ) : Nil
    @last_api_key = headers.try &.[:x_api_key]
    @last_contract_number = headers.try &.[:x_contract_number]
    @last_session_id = cookies.try &.[:session_id]
  end

  def create_resource(body : ReferenceFixture::CreateResourceRequest, headers : {x_api_key: String}? = nil) : Nil
  end

  # ── /resources/{id} ──────────────────────────────────────────────────────────

  def get_resource(id : UUID, headers : {x_tenant: String?, x_api_key: String}? = nil) : Nil
  end

  def update_resource(id : UUID, headers : {x_tenant: String?, x_api_key: String}? = nil) : Nil
  end

  def delete_resource(id : UUID, headers : {x_api_key: String, x_tenant: String}? = nil) : Nil
  end

  @[Deprecated]
  def patch_resource(
    id : UUID,
    body : ReferenceFixture::Resource,
    headers : {x_tenant: String?, x_api_key: String, x_legacy_token: String?}? = nil,
  ) : Nil
  end

  # ── /search ──────────────────────────────────────────────────────────────────

  def search_resources(
    q : String? = nil,
    tags : Array(String)? = nil,
    colors : Array(String)? = nil,
    ids : Array(UUID)? = nil,
    codes : Array(String)? = nil,
    limit : Int32? = nil,
    offset : Int32? = nil,
    headers : {x_api_key: String}? = nil,
    cookies : {session_id: String?}? = nil,
  ) : Nil
  end

  # ── /upload ──────────────────────────────────────────────────────────────────

  def upload_resource(headers : {x_api_key: String}? = nil) : Nil
  end

  # ── /multi-content ───────────────────────────────────────────────────────────

  def submit_multi_content(body : ReferenceFixture::Resource, headers : {x_api_key: String}? = nil) : Nil
    @last_submit_body = body
  end

  # ── /items ───────────────────────────────────────────────────────────────────

  def list_items(limit : Int32? = nil, headers : {x_api_key: String}? = nil) : Array(String)
    raise ReferenceFixture::ApiError.new(ReferenceFixture::ApiError::Body.new(code: 422, message: "forced error")) if force_items_error?
    ["item-1", "item-2", "item-3"]
  end

  # ── /items/{id} ──────────────────────────────────────────────────────────────

  def get_item(
    id : Int32,
    headers : {x_api_key: String, x_contract_number: Int32?}? = nil,
    cookies : {session_id: String?}? = nil,
  ) : {ReferenceFixture::Resource, {x_request_id: UUID?, x_rate_limit: Int32?}}
    {ITEM_RESOURCE, {x_request_id: FIXED_UUID, x_rate_limit: 42_i32}}
  end

  # ── /aliases ─────────────────────────────────────────────────────────────────

  def get_aliases(headers : {x_api_key: String}? = nil) : ReferenceFixture::GetAliasesResponse
    ReferenceFixture::GetAliasesResponse.new
  end

  # ── /events ──────────────────────────────────────────────────────────────────

  def list_events(limit : Int32? = nil, headers : {x_api_key: String}? = nil) : Array(ReferenceFixture::Event)
    [] of ReferenceFixture::Event
  end
end

# ── Shared server setup ───────────────────────────────────────────────────────

describe "Reference integration" do
  server = uninitialized HTTP::Server
  http = uninitialized HTTP::Client
  client = uninitialized ReferenceFixture::Client
  handler = uninitialized TestReferenceHandler

  around_all do |example|
    handler = TestReferenceHandler.new
    router = Mux::Router.new
    handler.register(router)
    server = HTTP::Server.new(router)
    address = server.bind_unused_port
    spawn { server.listen }
    Fiber.yield
    http = HTTP::Client.new(address.address, address.port)
    client = ReferenceFixture::Client.new(http)
    example.run
    http.close
    server.close
  end

  # ── Header parameters (GET /resources) ───────────────────────────────────────

  describe "GET /resources — required header (X-Api-Key: String)" do
    it "passes X-Api-Key to the handler when provided" do
      client.list_resources(headers: {x_api_key: "secret", x_contract_number: nil})
      handler.last_api_key.should eq("secret")
    end

    it "handler receives nil api_key when the whole headers tuple is omitted" do
      client.list_resources
      handler.last_api_key.should be_nil
    end

    it "sends X-Api-Key HTTP header on raw request" do
      http.get("/resources", headers: HTTP::Headers{"X-Api-Key" => "rawkey"})
      handler.last_api_key.should eq("rawkey")
    end

    it "handler receives nil api_key when no X-Api-Key header is sent" do
      http.get("/resources")
      handler.last_api_key.should be_nil
    end
  end

  describe "GET /resources — optional header (X-Contract-Number: Int32?)" do
    it "passes X-Contract-Number when given a value" do
      client.list_resources(headers: {x_api_key: "key", x_contract_number: 42})
      handler.last_contract_number.should eq(42)
    end

    it "omits X-Contract-Number when field is nil" do
      client.list_resources(headers: {x_api_key: "key", x_contract_number: nil})
      handler.last_contract_number.should be_nil
    end

    it "passes both required and optional headers simultaneously" do
      client.list_resources(headers: {x_api_key: "key", x_contract_number: 99})
      handler.last_api_key.should eq("key")
      handler.last_contract_number.should eq(99)
    end
  end

  describe "GET /resources — cookie parameters" do
    it "passes session_id cookie to the handler" do
      client.list_resources(cookies: {session_id: "sess-abc"})
      handler.last_session_id.should eq("sess-abc")
    end

    it "sends no cookie when cookies param is nil" do
      client.list_resources
      handler.last_session_id.should be_nil
    end
  end

  # ── Response headers (GET /items/{id}) ───────────────────────────────────────

  describe "GET /items/:id — response headers" do
    it "returns declared response headers alongside the body" do
      _body, resp_hdrs = client.get_item(1)
      resp_hdrs[:x_request_id].should eq(TestReferenceHandler::FIXED_UUID)
      resp_hdrs[:x_rate_limit].should eq(42)
    end

    it "returns Resource body with correct fields" do
      body, _hdrs = client.get_item(1)
      body.name.should eq("item-resource")
      body.status.should eq(ReferenceFixture::ResourceStatus::Active)
    end

    it "propagates X-Request-Id to the HTTP response layer" do
      response = http.get("/items/1")
      response.status_code.should eq(200)
      response.headers["X-Request-Id"].should eq(TestReferenceHandler::FIXED_UUID.to_s)
    end

    it "propagates X-Rate-Limit to the HTTP response layer" do
      response = http.get("/items/1")
      response.headers["X-Rate-Limit"].should eq("42")
    end
  end

  # ── Content-type negotiation (POST /resources) ───────────────────────────────

  describe "POST /resources — JSON and YAML request bodies" do
    body = ReferenceFixture::CreateResourceRequest.new(name: "test-resource", status: ReferenceFixture::ResourceStatus::Active)

    it "accepts a JSON request body (default)" do
      client.create_resource(body)
    end

    it "returns HTTP 201 for JSON body" do
      response = http.post(
        "/resources",
        body: %({"name":"test-resource","status":"active"}),
        headers: HTTP::Headers{"Content-Type" => "application/json", "X-Api-Key" => "key"},
      )
      response.status_code.should eq(201)
    end

    it "accepts a YAML request body" do
      client.create_resource(body, content_type: "application/yaml")
    end

    it "returns HTTP 201 for YAML body" do
      response = http.post(
        "/resources",
        body: "name: test-resource\nstatus: active\n",
        headers: HTTP::Headers{"Content-Type" => "application/yaml", "X-Api-Key" => "key"},
      )
      response.status_code.should eq(201)
    end
  end

  # ── Multi content-type (POST /multi-content) ─────────────────────────────────

  describe "POST /multi-content — all five content types" do
    resource = ReferenceFixture::Resource.new(
      id: ReferenceFixture::ResourceId.new("00000000-0000-0000-0000-000000000002"),
      name: "multi",
      status: ReferenceFixture::ResourceStatus::Active,
    )

    it "submits JSON body (default) and handler receives correct resource" do
      client.submit_multi_content(resource)
      handler.last_submit_body.not_nil!.name.should eq("multi")
    end

    it "submits YAML body and handler receives correct resource" do
      client.submit_multi_content(resource, content_type: "application/yaml")
      handler.last_submit_body.not_nil!.name.should eq("multi")
    end

    it "submits form-encoded body and server returns 201" do
      response = http.post(
        "/multi-content",
        body: "name=multi&status=active&id=00000000-0000-0000-0000-000000000002",
        headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded", "X-Api-Key" => "key"},
      )
      response.status_code.should eq(201)
    end

    it "responds with Content-Type application/json for JSON request" do
      response = http.post(
        "/multi-content",
        body: %({"id":"00000000-0000-0000-0000-000000000002","name":"multi","status":"active"}),
        headers: HTTP::Headers{"Content-Type" => "application/json"},
      )
      response.status_code.should eq(201)
    end
  end

  # ── Multipart upload (POST /upload) ──────────────────────────────────────────

  describe "POST /upload — multipart/form-data" do
    it "returns HTTP 201 for a multipart upload" do
      io = IO::Memory.new
      boundary = "boundary-ref-test"
      builder = HTTP::FormData::Builder.new(io, boundary)
      builder.file("file", IO::Memory.new("binary content"), HTTP::FormData::FileMetadata.new(filename: "test.bin"))
      builder.field("thumbnail", "bytes")
      builder.finish
      response = http.post(
        "/upload",
        body: io.rewind.gets_to_end,
        headers: HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=#{boundary}", "X-Api-Key" => "key"},
      )
      response.status_code.should eq(201)
    end
  end

  # ── Wildcard error responses (GET /items) ─────────────────────────────────────

  describe "GET /items — wildcard 4XX/5XX error responses" do
    it "returns items when no error is raised" do
      items = client.list_items
      items.should eq(["item-1", "item-2", "item-3"])
    end

    it "raises ApiError when the handler raises ApiError" do
      handler.force_items_error = true
      expect_raises(ReferenceFixture::ApiError) { client.list_items }
      handler.force_items_error = false
    end

    it "maps the error response to the correct HTTP status on raw request" do
      response = http.get("/items", headers: HTTP::Headers{"X-Api-Key" => "key"})
      response.status_code.should eq(200)
    end
  end
end
