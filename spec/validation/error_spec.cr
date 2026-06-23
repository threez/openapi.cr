require "../spec_helper"

describe OpenAPI::Validation::Error do
  it "exposes all fields via getters" do
    err = OpenAPI::Validation::Error.new("age", "200", "age 200 exceeds maximum 150", "maximum", "150")
    err.field.should eq("age")
    err.value.should eq("200")
    err.message.should eq("age 200 exceeds maximum 150")
    err.constraint.should eq("maximum")
    err.constraint_value.should eq("150")
  end

  it "to_s outputs the message" do
    err = OpenAPI::Validation::Error.new("age", "200", "age 200 exceeds maximum 150", "maximum", "150")
    err.to_s.should eq("age 200 exceeds maximum 150")
  end
end

describe OpenAPI::Validation::Exception do
  it "wraps multiple errors and joins messages" do
    errors = [
      OpenAPI::Validation::Error.new("age", "200", "age 200 exceeds maximum 150", "maximum", "150"),
      OpenAPI::Validation::Error.new("name", "", "name length 0 is below minLength 1", "minLength", "1"),
    ]
    ex = OpenAPI::Validation::Exception.new(errors)
    ex.errors.size.should eq(2)
    ex.message.should eq("age 200 exceeds maximum 150; name length 0 is below minLength 1")
  end

  it "raises as an Exception" do
    errors = [OpenAPI::Validation::Error.new("x", "1", "x 1 < 5", "minimum", "5")]
    expect_raises(OpenAPI::Validation::Exception, "x 1 < 5") do
      raise OpenAPI::Validation::Exception.new(errors)
    end
  end
end
