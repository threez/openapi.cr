require "../spec_helper"

module EnumMacroSpec
  openapi_enum Status do
    Active   = "active"
    Inactive = "inactive"
  end

  openapi_enum Priority do
    Low  = 1
    High = 2
  end

  openapi_enum State do
    ACTIVE
    FAILED
    InProgress = "in-progress"
  end

  openapi_extensible_enum Protocol do
    TCP
    Http   = "http"
    Custom = "custom-value"
  end

  openapi_enum YamlStatus, yaml: true do
    Active   = "active"
    Inactive = "inactive"
  end

  openapi_extensible_enum YamlProtocol, yaml: true do
    TCP
    Http = "http"
  end
end

describe "openapi_enum" do
  it "deserialises a string enum from JSON" do
    pull = JSON::PullParser.new(%("active"))
    EnumMacroSpec::Status.from_json(pull).should eq(EnumMacroSpec::Status::Active)
  end

  it "raises on unknown string value" do
    pull = JSON::PullParser.new(%("unknown"))
    expect_raises(JSON::ParseException, /Unknown Status/) do
      EnumMacroSpec::Status.from_json(pull)
    end
  end

  it "serialises a string enum to JSON" do
    io = IO::Memory.new
    builder = JSON::Builder.new(io)
    builder.document { EnumMacroSpec::Status::Active.to_json(builder) }
    io.to_s.should eq(%("active"))
  end

  it "deserialises an integer enum from JSON" do
    pull = JSON::PullParser.new("1")
    EnumMacroSpec::Priority.from_json(pull).should eq(EnumMacroSpec::Priority::Low)
  end

  it "raises on unknown integer value" do
    pull = JSON::PullParser.new("99")
    expect_raises(JSON::ParseException, /Unknown Priority/) do
      EnumMacroSpec::Priority.from_json(pull)
    end
  end

  it "serialises an integer enum to JSON" do
    io = IO::Memory.new
    builder = JSON::Builder.new(io)
    builder.document { EnumMacroSpec::Priority::High.to_json(builder) }
    io.to_s.should eq("2")
  end

  it "derives wire from all-caps member name (identity)" do
    pull = JSON::PullParser.new(%("ACTIVE"))
    EnumMacroSpec::State.from_json(pull).should eq(EnumMacroSpec::State::ACTIVE)
  end

  it "serialises all-caps member to its own name" do
    io = IO::Memory.new
    builder = JSON::Builder.new(io)
    builder.document { EnumMacroSpec::State::FAILED.to_json(builder) }
    io.to_s.should eq(%("FAILED"))
  end

  it "honours explicit wire value alongside plain all-caps members" do
    pull = JSON::PullParser.new(%("in-progress"))
    EnumMacroSpec::State.from_json(pull).should eq(EnumMacroSpec::State::InProgress)
  end

  describe "openapi_extensible_enum" do
    it "constructs known constant from all-caps wire (identity)" do
      EnumMacroSpec::Protocol::TCP.value.should eq("TCP")
    end

    it "deserialises known value from JSON" do
      pull = JSON::PullParser.new(%("http"))
      EnumMacroSpec::Protocol.from_json(pull).value.should eq("http")
    end

    it "accepts unknown wire values (extensible)" do
      pull = JSON::PullParser.new(%("grpc"))
      p = EnumMacroSpec::Protocol.from_json(pull)
      p.value.should eq("grpc")
      p.known?.should be_false
      p.unknown?.should be_true
    end

    it "serialises to JSON" do
      io = IO::Memory.new
      builder = JSON::Builder.new(io)
      builder.document { EnumMacroSpec::Protocol::TCP.to_json(builder) }
      io.to_s.should eq(%("TCP"))
    end

    it "exposes predicate helpers" do
      EnumMacroSpec::Protocol::TCP.tcp?.should be_true
      EnumMacroSpec::Protocol::Http.tcp?.should be_false
      EnumMacroSpec::Protocol.new("custom-value").custom_value?.should be_true
    end
  end

  describe "explicit format params" do
    it "deserialises enum from YAML when yaml: true" do
      EnumMacroSpec::YamlStatus.from_yaml("active").should eq(EnumMacroSpec::YamlStatus::Active)
    end

    it "serialises enum to YAML when yaml: true" do
      EnumMacroSpec::YamlStatus::Inactive.to_yaml.strip.should eq("--- inactive")
    end

    it "deserialises extensible enum from YAML when yaml: true" do
      EnumMacroSpec::YamlProtocol.from_yaml("http").value.should eq("http")
    end

    it "serialises extensible enum to YAML when yaml: true" do
      EnumMacroSpec::YamlProtocol::TCP.to_yaml.strip.should eq("--- TCP")
    end
  end
end
