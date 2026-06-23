# DSL macro for generating an OpenAPI enum with built-in `from_json` / `to_json`.
#
# Each member's wire value is declared inline with `=`:
#
# ```
# openapi_enum Status do
#   Active   = "active"
#   Inactive = "inactive"
# end
# ```
#
# Integer enums use bare integer assignments (valid Crystal enum syntax):
#
# ```
# openapi_enum Priority do
#   Low  = 1
#   High = 2
# end
# ```
#
# Members without an explicit wire value fall back to `member_name.downcase`
# (or `member_name` itself for all-caps identifiers):
#
# ```
# openapi_enum Simple do
#   Foo # wire: "foo"
#   BAR # wire: "BAR"
# end
# ```
macro openapi_enum(name, json = true, yaml = false, xml = false, form = nil, multipart = false, &block)
  # Build wire→crystal mapping at expansion time from the block AST.
  {% mapping = {} of String => String %}
  {% is_int = false %}
  {% exprs = block.body.is_a?(Expressions) ? block.body.expressions : [block.body] %}
  {% for expr in exprs %}
    {% if expr.is_a?(Assign) %}
      {% if expr.value.is_a?(NumberLiteral) %}
        {% is_int = true %}
        {% mapping[expr.value.stringify] = expr.target.id.stringify %}
      {% elsif expr.value.is_a?(StringLiteral) %}
        {% mapping[expr.value] = expr.target.id.stringify %}
      {% end %}
    {% elsif expr.is_a?(Path) %}
      {% member_str = expr.id.stringify %}
      {% if member_str == member_str.upcase %}
        {% mapping[member_str] = member_str %}
      {% else %}
        {% mapping[member_str.downcase] = member_str %}
      {% end %}
    {% end %}
  {% end %}

  enum {{name.id}}
    # Emit member names only — strip string wire assignments (invalid in enum
    # bodies), pass integer assignments through (valid Crystal enum syntax).
    {% for expr in exprs %}
      {% if expr.is_a?(Assign) && expr.value.is_a?(StringLiteral) %}
        {{expr.target.id}}
      {% else %}
        {{expr}}
      {% end %}
    {% end %}

    def wire_value : String
      {% if is_int %}
      value.to_s
      {% else %}
      case self
      {% for wire, member in mapping %}
      when {{member.id}} then {{wire}}
      {% end %}
      else to_s.downcase
      end
      {% end %}
    end

    {% if json %}
    def self.from_json(pull : ::JSON::PullParser) : self
      value = pull.{% if is_int %}read_int{% else %}read_string{% end %}
      case value
      {% for wire, member in mapping %}
      when {% if is_int %}{{wire.id}}{% else %}{{wire}}{% end %} then {{member.id}}
      {% end %}
      else raise ::JSON::ParseException.new("Unknown {{name.id}}: #{value}", 0, 0)
      end
    end

    def to_json(builder : ::JSON::Builder)
      (case self
      {% for wire, member in mapping %}
      when {{member.id}} then {% if is_int %}{{wire.id}}{% else %}{{wire}}{% end %}
      {% end %}
      else {% if is_int %}value.to_i64{% else %}to_s.downcase{% end %}
      end).to_json(builder)
    end

    def self.from_wire(s : String) : self
      {% if is_int %}
      from_json(::JSON::PullParser.new(s))
      {% else %}
      from_json(::JSON::PullParser.new(%("#{s}")))
      {% end %}
    end
    {% end %}

    {% if yaml %}
    def self.new(ctx : ::YAML::ParseContext, node : ::YAML::Nodes::Node) : self
      node.raise "Expected scalar" unless node.is_a?(::YAML::Nodes::Scalar)
      {% if is_int %}
      from_json(::JSON::PullParser.new(node.value))
      {% else %}
      from_json(::JSON::PullParser.new(%("#{node.value}")))
      {% end %}
    end

    def to_yaml(yaml : ::YAML::Nodes::Builder)
      yaml.scalar wire_value
    end
    {% end %}
  end
end

# DSL macro for generating an OpenAPI extensible-enum value struct with
# predicate helpers and built-in JSON/YAML serialization.
#
# Unlike `openapi_enum`, this generates a struct (not a Crystal enum) so the
# value can hold unknown wire strings the generator hasn't enumerated.
#
# Known members are declared exactly like `openapi_enum`:
#
# ```
# openapi_extensible_enum Protocol do
#   TCP           # wire: "TCP"   (all-caps → identity)
#   Http = "http" # wire: "http"  (explicit)
# end
# ```
macro openapi_extensible_enum(name, json = true, yaml = false, xml = false, form = nil, multipart = false, &block)
  # Build wire→crystal mapping at expansion time (same rules as openapi_enum).
  {% mapping = {} of String => String %}
  {% exprs = block.body.is_a?(Expressions) ? block.body.expressions : [block.body] %}
  {% for expr in exprs %}
    {% if expr.is_a?(Assign) && expr.value.is_a?(StringLiteral) %}
      {% mapping[expr.value] = expr.target.id.stringify %}
    {% elsif expr.is_a?(Path) %}
      {% member_str = expr.id.stringify %}
      {% if member_str == member_str.upcase %}
        {% mapping[member_str] = member_str %}
      {% else %}
        {% mapping[member_str.downcase] = member_str %}
      {% end %}
    {% end %}
  {% end %}

  struct {{name.id}}
    {% for wire, member in mapping %}
    {{member.id}} = new({{wire}})
    {% end %}

    getter value : String

    def initialize(@value : String)
    end

    {% for wire, member in mapping %}
    {% pred = wire.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/^_+/, "") %}
    def {{pred.id}}? : Bool
      @value == {{wire}}
    end
    {% end %}

    def known? : Bool
      case @value
      {% for wire, _ in mapping %}
      when {{wire}} then true
      {% end %}
      else false
      end
    end

    # Emit unknown? only when none of the known predicates is already named "unknown"
    {% has_unknown = false %}
    {% for wire, _ in mapping %}
      {% if wire.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/^_+/, "") == "unknown" %}
        {% has_unknown = true %}
      {% end %}
    {% end %}
    {% unless has_unknown %}
    def unknown? : Bool
      case @value
      {% for wire, _ in mapping %}
      when {{wire}} then false
      {% end %}
      else true
      end
    end
    {% end %}

    {% if json %}
    def self.new(pull : ::JSON::PullParser) : self
      new(pull.read_string)
    end

    def self.from_json(pull : ::JSON::PullParser) : self
      new(pull.read_string)
    end

    def to_json(builder : ::JSON::Builder)
      @value.to_json(builder)
    end
    {% end %}

    {% if yaml %}
    def self.new(ctx : ::YAML::ParseContext, node : ::YAML::Nodes::Node) : self
      node.raise "Expected scalar" unless node.is_a?(::YAML::Nodes::Scalar)
      new(node.value)
    end

    def to_yaml(yaml : ::YAML::Nodes::Builder)
      yaml.scalar @value
    end
    {% end %}

    def ==(other : self) : Bool
      @value == other.value
    end

    {% if form %}
    include {{form.id}}

    def self.from_form_params(params : ::HTTP::Params, prefix : String? = nil) : self
      new(prefix ? params[prefix] : params["value"])
    end

    def _form_append(p : ::HTTP::Params::Builder, prefix : String?) : Nil
      p.add(prefix || "value", @value)
    end

    def to_form_params : String
      ::HTTP::Params.build { |_p| _form_append(_p, nil) }
    end
    {% end %}
  end
end
