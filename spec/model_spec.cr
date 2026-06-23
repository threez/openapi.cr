require "./spec_helper"

describe OpenAPI do
  describe OpenAPI::Model::Document do
    it "parses the Petstore YAML fixture" do
      doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
      doc.openapi.should start_with("3.")
      doc.info.title.should eq("Swagger Petstore")
      doc.paths.should_not be_nil
    end

    it "exposes path items" do
      doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
      paths = doc.paths.not_nil!
      paths.keys.should_not be_empty
    end

    it "exposes GET operation on /pets" do
      doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
      pets = doc.paths.not_nil!["/pets"]
      pets.get.should_not be_nil
      pets.get.not_nil!.operation_id.should eq("listPets")
    end

    it "exposes components schemas" do
      doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
      schemas = doc.components.not_nil!.schemas.not_nil!
      schemas.keys.should contain("Pet")
    end

    it "parses schema properties" do
      doc = OpenAPI::Model::Document.from_file("spec/fixtures/petstore.yaml")
      pet_ref = doc.components.not_nil!.schemas.not_nil!["Pet"]
      pet_ref.ref?.should be_false
      pet = pet_ref.resolved
      pet.properties.should_not be_nil
    end
  end

  describe "fixture parsing" do
    {
      "spec/fixtures/petstore.yaml"       => {title: "Swagger Petstore", paths: 2, schemas: 5},
      "spec/fixtures/ionos-nfs-v1.yaml"   => {title: "IONOS CLOUD - Network File Storage API", paths: 4, schemas: 19},
      "spec/fixtures/google-storage.yaml" => {title: "Cloud Storage JSON API", paths: 26, schemas: 20},
      "spec/fixtures/ionos-cloud-v6.json" => {title: "CLOUD API", paths: 124, schemas: 228},
      "spec/fixtures/stripe.json"         => {title: "Stripe API", paths: 297, schemas: 725},
    }.each do |path, expected|
      it "parses #{File.basename(path)}" do
        doc = OpenAPI::Model::Document.from_file(path)
        doc.info.title.should eq(expected[:title])
        doc.paths.try(&.size).should eq(expected[:paths])
        doc.components.try(&.schemas).try(&.size).should eq(expected[:schemas])
      end
    end
  end

  describe OpenAPI::Model::OrRef do
    it "stores ref string" do
      or_ref = OpenAPI::Model::OrRef(OpenAPI::Model::Schema).new(ref: "#/components/schemas/Pet")
      or_ref.ref?.should be_true
      or_ref.ref.should eq("#/components/schemas/Pet")
    end

    it "stores inline value" do
      schema = OpenAPI::Model::Schema.from_yaml("type: string\n")
      or_ref = OpenAPI::Model::OrRef(OpenAPI::Model::Schema).new(value: schema)
      or_ref.ref?.should be_false
      or_ref.resolved.type.should eq("string")
    end
  end
end
