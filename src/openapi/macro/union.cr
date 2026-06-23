# Generates a typed union wrapper struct for OpenAPI oneOf/anyOf schemas.
#
# Try-each (no discriminator):
#   openapi_union Pet, {Cat, Dog, Bird}
#
# Discriminator-based (with explicit mapping):
#   openapi_union DiscriminatedPet, {Cat, Dog},
#     discriminator: "petType",
#     mapping: {"cat" => Cat, "dog" => Dog}
#
# Discriminator-based (implicit mapping — wire values equal schema names):
#   openapi_union ImplicitPet, {Cat, Dog}, discriminator: "type"
#
# Format args (all default false/nil — only pass what the generated file requires):
#   openapi_union Pet, {Cat, Dog}, yaml: true, xml: true,
#     form: OpenAPI::Form::Serializable, multipart: true
macro openapi_union(name, types, discriminator = nil, mapping = nil,
                    json = true, yaml = false, xml = false, form = nil, multipart = false)
  struct {{ name.id }}
    getter value : {% for t, i in types %}{% if i > 0 %} | {% end %}{{ t }}{% end %}

    def initialize(@value : {% for t, i in types %}{% if i > 0 %} | {% end %}{{ t }}{% end %})
    end

    {% if json %}
    def initialize(pull : ::JSON::PullParser)
      _raw = pull.read_raw
      {% if discriminator %}
        case ::JSON.parse(_raw)[{{ discriminator }}]?.try(&.as_s?)
        {% if mapping %}
          {% for wire, type in mapping %}
          when {{ wire }} then @value = {{ type }}.from_json(_raw)
          {% end %}
        {% else %}
          {% for t in types %}
          when {{ t.stringify }} then @value = {{ t }}.from_json(_raw)
          {% end %}
        {% end %}
        else
          raise ::JSON::ParseException.new("Unknown {{ name.id }} discriminator value", 0, 0)
        end
      {% else %}
        {% for t in types %}
        begin
          @value = {{ t }}.from_json(_raw)
          return
        rescue ::JSON::ParseException
        end
        {% end %}
        raise ::JSON::ParseException.new(
          "Cannot deserialize {{ name.id }} ({% for t, i in types %}{% if i > 0 %} | {% end %}{{ t }}{% end %})", 0, 0)
      {% end %}
    end

    def to_json(json : ::JSON::Builder) : Nil
      @value.to_json(json)
    end
    {% end %}

    {% if yaml %}
    def to_yaml(yaml : ::YAML::Nodes::Builder) : Nil
      @value.to_yaml(yaml)
    end
    {% end %}

    {% if xml %}
    def to_xml : String
      @value.to_xml
    end

    def self.from_xml(input : String | IO) : self
      _raw = input.is_a?(IO) ? input.gets_to_end : input
      {% if discriminator %}
        _doc = ::XML.parse(_raw)
        _disc = _doc.first_element_child.try { |el|
          el[{{ discriminator }}]? ||
            el.children.find { |c| c.element? && c.name == {{ discriminator }} }.try(&.text)
        }
        case _disc
        {% if mapping %}
          {% for wire, type in mapping %}
          when {{ wire }} then new({{ type }}.from_xml(_raw))
          {% end %}
        {% else %}
          {% for t in types %}
          when {{ t.stringify }} then new({{ t }}.from_xml(_raw))
          {% end %}
        {% end %}
        else
          raise ::XML::Error.new("Unknown {{ name.id }} discriminator: #{_disc}", 0)
        end
      {% else %}
        {% for t in types %}
        begin
          return new({{ t }}.from_xml(_raw))
        rescue ::XML::Error
        end
        {% end %}
        raise ::XML::Error.new(
          "Cannot deserialize {{ name.id }} ({% for t, i in types %}{% if i > 0 %} | {% end %}{{ t }}{% end %}) from XML", 0)
      {% end %}
    end
    {% end %}

    {% if form %}
    def to_form_params : String
      @value.to_form_params
    end

    def self.from_form_params(params : ::HTTP::Params, prefix : String? = nil) : self
      {% if discriminator %}
        _disc_key = prefix ? "#{prefix}[{{ discriminator.id }}]" : {{ discriminator }}
        case params[_disc_key]?
        {% if mapping %}
          {% for wire, type in mapping %}
          when {{ wire }} then new({{ type }}.from_form_params(params, prefix))
          {% end %}
        {% else %}
          {% for t in types %}
          when {{ t.stringify }} then new({{ t }}.from_form_params(params, prefix))
          {% end %}
        {% end %}
        else
          raise "Unknown {{ name.id }} discriminator in form params"
        end
      {% else %}
        {% for t in types %}
        begin
          return new({{ t }}.from_form_params(params, prefix))
        rescue
        end
        {% end %}
        raise "Cannot deserialize {{ name.id }} from form params"
      {% end %}
    end
    {% end %}

    {% if multipart %}
    def to_multipart(builder : ::HTTP::FormData::Builder) : Nil
      @value.to_multipart(builder)
    end

    def self.from_multipart(request : ::HTTP::Request) : self
      {% if discriminator %}
        _disc_val = nil
        ::HTTP::FormData.parse(request) do |_part|
          _disc_val = _part.body.gets_to_end if _part.name == {{ discriminator }}
        end
        case _disc_val
        {% if mapping %}
          {% for wire, type in mapping %}
          when {{ wire }}
            new({{ type }}.from_multipart(request))
          {% end %}
        {% else %}
          {% for t in types %}
          when {{ t.stringify }}
            new({{ t }}.from_multipart(request))
          {% end %}
        {% end %}
        else
          raise "Unknown {{ name.id }} discriminator in multipart"
        end
      {% else %}
        {% for t in types %}
        begin
          return new({{ t }}.from_multipart(request))
        rescue
        end
        {% end %}
        raise "Cannot deserialize {{ name.id }} from multipart"
      {% end %}
    end
    {% end %}
  end
end
