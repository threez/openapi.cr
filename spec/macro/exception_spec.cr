require "../spec_helper"

module ExceptionMacroSpec
  openapi_exception ApiError do
    getter code : Int32     # ameba:disable Lint/UselessAssign
    getter message : String # ameba:disable Lint/UselessAssign

    def initialize(@code : Int32, @message : String)
    end
  end

  openapi_exception CodeOnlyError do
    getter code : Int32 # ameba:disable Lint/UselessAssign

    def initialize(@code : Int32)
    end
  end

  openapi_exception YamlError, yaml: true do
    getter code : Int32     # ameba:disable Lint/UselessAssign
    getter message : String # ameba:disable Lint/UselessAssign

    def initialize(@code : Int32, @message : String)
    end
  end
end

describe "openapi_exception macro" do
  it "creates an Exception subclass" do
    err = ExceptionMacroSpec::ApiError.from_json(%({"code": 1, "message": "x"}))
    err.should be_a(Exception)
  end

  it "deserializes from JSON and delegates body properties" do
    err = ExceptionMacroSpec::ApiError.from_json(%({"code": 42, "message": "oops"}))
    err.code.should eq(42)
    err.message.should eq("oops")
  end

  it "serializes to JSON via Body delegation" do
    body = ExceptionMacroSpec::ApiError::Body.new(code: 1, message: "hi")
    err = ExceptionMacroSpec::ApiError.new(body)
    err.to_json.should eq(%({"code":1,"message":"hi"}))
  end

  it "sets exception message from message property (super(@body.message))" do
    err = ExceptionMacroSpec::ApiError.from_json(%({"code": 5, "message": "bad request"}))
    err.message.should eq("bad request")
  end

  it "falls back to @body.inspect when no message property" do
    err = ExceptionMacroSpec::CodeOnlyError.from_json(%({"code": 99}))
    err.message.should contain("99")
  end

  it "delegates properties via forward_missing_to" do
    body = ExceptionMacroSpec::ApiError::Body.new(code: 7, message: "test")
    err = ExceptionMacroSpec::ApiError.new(body)
    err.code.should eq(7)
  end

  it "deserializes from YAML with yaml: true" do
    err = ExceptionMacroSpec::YamlError.from_yaml("code: 10\nmessage: yaml-err\n")
    err.code.should eq(10)
    err.message.should eq("yaml-err")
  end

  it "serializes to YAML via Body delegation" do
    body = ExceptionMacroSpec::YamlError::Body.new(code: 3, message: "y")
    err = ExceptionMacroSpec::YamlError.new(body)
    err.to_yaml.should contain("code: 3")
    err.to_yaml.should contain("message: y")
  end
end
