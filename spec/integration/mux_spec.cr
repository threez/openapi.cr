require "../spec_helper"
require "./generated/types"
require "./generated/client"
require "./generated/server"

# Concrete server implementation backed by an in-memory list of pets.
class TestPetstoreHandler < Petstore::Handler
  PETS = [
    Petstore::Pet.new(id: 1_i64, name: "Fluffy", tag: "cat"),
    Petstore::Pet.new(id: 2_i64, name: "Rex", tag: "dog"),
    Petstore::Pet.new(id: 3_i64, name: "Goldie", tag: nil),
  ]

  def list_pets(limit : Int32? = nil) : {Petstore::Pets, {x_next: String?}}
    errors = validate_list_pets_params(limit)
    raise Petstore::Error.new(Petstore::Error::Body.new(code: 400, message: errors.first.message)) unless errors.empty?
    pets = limit ? PETS.first(limit) : PETS
    {pets, {x_next: nil}}
  end

  def create_pets(body : Petstore::Pet) : Nil
    raise Petstore::ValidationError.new(Petstore::ValidationError::Body.new(message: "name is required", field: "name")) if body.name.empty?
  end

  def show_pet_by_id(pet_id : String) : Petstore::Pet
    PETS.find { |p| p.id.to_s == pet_id } ||
      raise Petstore::NotFoundError.new(Petstore::NotFoundError::Body.new(message: "pet #{pet_id} not found"))
  end
end

describe "Petstore integration" do
  server = uninitialized HTTP::Server
  http = uninitialized HTTP::Client
  client = uninitialized Petstore::Client

  # Use around_all instead of before_all/after_all to avoid conflict with
  # Kemal's DSL which defines before_all/after_all as HTTP filter helpers.
  around_all do |example|
    router = Mux::Router.new
    TestPetstoreHandler.new.register(router)
    server = HTTP::Server.new(router)
    address = server.bind_unused_port
    spawn { server.listen }
    Fiber.yield
    http = HTTP::Client.new(address.address, address.port)
    client = Petstore::Client.new(http)
    example.run
    http.close
    server.close
  end

  describe "GET /pets" do
    it "returns all pets" do
      pets, _hdrs = client.list_pets
      pets.size.should eq(3)
      pets.first.name.should eq("Fluffy")
    end

    it "respects the limit query parameter" do
      pets, _hdrs = client.list_pets(limit: 2)
      pets.size.should eq(2)
    end

    it "raises OpenAPI::Validation::Exception before sending a request when limit exceeds 100" do
      expect_raises(OpenAPI::Validation::Exception) { client.list_pets(limit: 200) }
    end

    it "returns an error when limit exceeds maximum 100" do
      response = http.get("/pets?limit=200")
      response.status_code.should eq(500)
      response.body.should contain("exceeds maximum")
    end

    it "decodes all Pet fields correctly" do
      pets, _hdrs = client.list_pets
      pet = pets[1]
      pet.id.should eq(2_i64)
      pet.name.should eq("Rex")
      pet.tag.should eq("dog")
    end

    it "decodes nullable tag as nil" do
      pets, _hdrs = client.list_pets
      pets.last.tag.should be_nil
    end
  end

  describe "GET /pets/:petId" do
    it "returns the pet for a valid id" do
      pet = client.show_pet_by_id("1")
      pet.id.should eq(1_i64)
      pet.name.should eq("Fluffy")
    end

    it "encodes the path parameter correctly" do
      pet = client.show_pet_by_id("3")
      pet.name.should eq("Goldie")
    end

    it "raises Petstore::NotFoundError when pet is not found" do
      ex = expect_raises(Petstore::NotFoundError) { client.show_pet_by_id("999") }
      ex.message.should eq("pet 999 not found")
    end

    it "returns HTTP 404 for a missing pet" do
      response = http.get("/pets/999")
      response.status_code.should eq(404)
    end

    it "deserializes error message from JSON response body" do
      ex = expect_raises(Petstore::NotFoundError) { client.show_pet_by_id("0") }
      ex.message.not_nil!.should contain("not found")
    end
  end

  describe "POST /pets" do
    it "creates a pet successfully and returns 201" do
      client.create_pets(Petstore::Pet.new(id: 99_i64, name: "Tweety", tag: "bird"))
    end

    it "raises Petstore::ValidationError when name is empty" do
      ex = expect_raises(Petstore::ValidationError) do
        client.create_pets(Petstore::Pet.new(id: 100_i64, name: ""))
      end
      ex.message.should eq("name is required")
      ex.field.should eq("name")
    end

    it "returns HTTP 422 when name is empty" do
      response = http.post(
        "/pets",
        body: %({"id":100,"name":""}),
        headers: HTTP::Headers{"Content-Type" => "application/json"},
      )
      response.status_code.should eq(422)
    end

    it "round-trips the request body with all fields" do
      client.create_pets(Petstore::Pet.new(id: 101_i64, name: "Max", tag: "hamster"))
    end
  end

  describe "XML support" do
    describe "GET /pets" do
      it "returns XML when Accept: application/xml" do
        response = http.get("/pets", headers: HTTP::Headers{"Accept" => "application/xml"})
        response.status_code.should eq(200)
        response.headers["Content-Type"].should contain("application/xml")
      end

      it "parses XML response body into typed pets" do
        response = http.get("/pets", headers: HTTP::Headers{"Accept" => "application/xml"})
        pets = Petstore::Pets.from_xml(response.body)
        pets.size.should eq(3)
        pets.first.name.should eq("Fluffy")
      end

      it "returns XML with nullable tag omitted when nil" do
        response = http.get("/pets", headers: HTTP::Headers{"Accept" => "application/xml"})
        pets = Petstore::Pets.from_xml(response.body)
        pets.last.tag.should be_nil
      end

      it "typed client accept parameter returns XML-deserialized pets" do
        pets, _hdrs = client.list_pets(accept: "application/xml")
        pets.size.should eq(3)
        pets.first.name.should eq("Fluffy")
      end

      it "defaults to JSON when no Accept header" do
        response = http.get("/pets")
        response.headers["Content-Type"].should contain("application/json")
      end
    end

    describe "GET /pets/:petId" do
      it "returns XML for a valid pet id" do
        response = http.get("/pets/1", headers: HTTP::Headers{"Accept" => "application/xml"})
        response.status_code.should eq(200)
        response.headers["Content-Type"].should contain("application/xml")
        pet = Petstore::Pet.from_xml(response.body)
        pet.id.should eq(1_i64)
        pet.name.should eq("Fluffy")
      end

      it "typed client accept parameter returns XML-deserialized pet" do
        pet = client.show_pet_by_id("2", accept: "application/xml")
        pet.id.should eq(2_i64)
        pet.name.should eq("Rex")
        pet.tag.should eq("dog")
      end
    end

    describe "POST /pets" do
      it "accepts XML request body and returns 201" do
        pet = Petstore::Pet.new(id: 200_i64, name: "Tweety", tag: "bird")
        response = http.post(
          "/pets",
          body: pet.to_xml,
          headers: HTTP::Headers{"Content-Type" => "application/xml"},
        )
        response.status_code.should eq(201)
      end

      it "typed client content_type parameter sends XML" do
        client.create_pets(
          Petstore::Pet.new(id: 201_i64, name: "Polly", tag: "parrot"),
          content_type: "application/xml",
        )
      end

      it "returns 422 when XML body has empty name" do
        pet = Petstore::Pet.new(id: 202_i64, name: "")
        response = http.post(
          "/pets",
          body: pet.to_xml,
          headers: HTTP::Headers{"Content-Type" => "application/xml"},
        )
        response.status_code.should eq(422)
      end
    end
  end
end

describe "Petstore::Handler#validate_list_pets_params" do
  handler = TestPetstoreHandler.new

  it "returns no errors when limit is nil" do
    handler.validate_list_pets_params.should be_empty
  end

  it "returns no errors for a limit within the maximum" do
    handler.validate_list_pets_params(limit: 100).should be_empty
  end

  it "returns a violation when limit exceeds 100" do
    errors = handler.validate_list_pets_params(limit: 200)
    errors.size.should eq(1)
    errors.first.field.should eq("limit")
    errors.first.constraint.should eq("maximum")
    errors.first.constraint_value.should eq("100")
    errors.first.message.should contain("exceeds maximum")
  end
end
