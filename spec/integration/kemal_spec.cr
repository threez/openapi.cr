require "../spec_helper"
require "kemal"
require "./generated/types"
require "./generated/client"
require "./generated/kemal_server"

class TestPetstoreKemalHandler < Petstore::Kemal::Handler
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

describe "Petstore Kemal integration" do
  server = uninitialized HTTP::Server
  http = uninitialized HTTP::Client
  client = uninitialized Petstore::Client

  around_all do |example|
    Kemal.config.logging = false
    TestPetstoreKemalHandler.new.register
    Kemal.config.setup
    server = HTTP::Server.new(Kemal.config.handlers)
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

    it "decodes nullable tag as nil" do
      pets, _hdrs = client.list_pets
      pets.last.tag.should be_nil
    end

    it "returns an error when limit exceeds maximum 100" do
      response = http.get("/pets?limit=200")
      response.status_code.should eq(500)
      response.body.should contain("exceeds maximum")
    end
  end

  describe "GET /pets/:petId" do
    it "returns the pet for a valid id" do
      pet = client.show_pet_by_id("1")
      pet.name.should eq("Fluffy")
    end

    it "raises Petstore::NotFoundError when pet is not found" do
      ex = expect_raises(Petstore::NotFoundError) { client.show_pet_by_id("999") }
      ex.message.should eq("pet 999 not found")
    end

    it "returns HTTP 404 for a missing pet" do
      response = http.get("/pets/999")
      response.status_code.should eq(404)
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
  end
end
