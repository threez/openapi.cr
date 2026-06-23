# Generates a delegate-based composition struct for OpenAPI allOf schemas
# where all entries are $refs with no extra properties.
#
# Example:
#   openapi_allof AllCreature, {Bird, Cat, Dog}
#
# Format args (all default false/nil — only pass what the generated file requires):
#   openapi_allof AllCreature, {Bird, Cat, Dog}, yaml: true, xml: true,
#     form: OpenAPI::Form::Serializable, multipart: true
#
# Expands to a struct with a typed field per component, an initialize that
# deserializes each from the same raw JSON, merged to_json/to_yaml, and
# delegated property access (first-mentioned type wins on duplicates).
macro openapi_allof(name, types, json = true, yaml = false, xml = false, form = nil, multipart = false)
  struct {{ name.id }}
    {% for t in types %}
    getter {{ t.id.underscore }} : {{ t }}
    {% end %}

    {% if json %}
    # Deserialize all components from the same raw JSON.
    def initialize(pull : ::JSON::PullParser)
      _raw = pull.read_raw
      {% for t in types %}
      @{{ t.id.underscore }} = {{ t }}.from_json(_raw)
      {% end %}
    end
    {% end %}

    # Named-field initialize — used by form/multipart/xml deserialization paths.
    def initialize({% for t in types %}@{{ t.id.underscore }} : {{ t }},{% end %})
    end

    {% if json %}
    private def _merged_json : ::JSON::Any
      _all = {} of String => ::JSON::Any
      {% for t in types %}
      ::JSON.parse(@{{ t.id.underscore }}.to_json).as_h.each { |k, v| _all[k] = v unless _all.has_key?(k) }
      {% end %}
      ::JSON::Any.new(_all)
    end

    def to_json(json : ::JSON::Builder) : Nil
      _merged_json.to_json(json)
    end
    {% end %}

    {% if yaml %}
    def to_yaml(yaml : ::YAML::Nodes::Builder) : Nil
      ::YAML.parse(_merged_json.to_json).to_yaml(yaml)
    end
    {% end %}

    {% if xml %}
    def to_xml : String
      ::XML.build(indent: "  ") do |xml|
        xml.element({{ name.id.stringify.downcase }}) do
          {% for t in types %}
          ::XML.parse(@{{ t.id.underscore }}.to_xml).first_element_child.try do |_el|
            _el.attributes.each { |_a| xml.attribute(_a.name, _a.value) }
            _el.children.each { |_c| xml << _c.to_s if _c.element? || _c.text? }
          end
          {% end %}
        end
      end
    end

    def self.from_xml(input : String | IO) : self
      _raw = input.is_a?(IO) ? input.gets_to_end : input
      new({% for t in types %}{{ t.id.underscore }}: {{ t }}.from_xml(_raw),{% end %})
    end
    {% end %}

    {% if form %}
    def to_form_params : String
      ::HTTP::Params.build do |_p|
        {% for t in types %}
        @{{ t.id.underscore }}._form_append(_p, nil)
        {% end %}
      end
    end

    def self.from_form_params(params : ::HTTP::Params, prefix : String? = nil) : self
      new({% for t in types %}{{ t.id.underscore }}: {{ t }}.from_form_params(params, prefix),{% end %})
    end
    {% end %}

    {% if multipart %}
    def to_multipart(builder : ::HTTP::FormData::Builder) : Nil
      {% for t in types %}
      @{{ t.id.underscore }}.to_multipart(builder)
      {% end %}
    end

    def self.from_multipart(request : ::HTTP::Request) : self
      # Buffer the body so each sub-type can read it independently.
      _raw = request.body.try(&.gets_to_end) || ""
      _ct  = request.headers["Content-Type"]?
      new({% for t in types %}
        {{ t.id.underscore }}: {{ t }}.from_multipart(
          ::HTTP::Request.new("POST", "/",
            ::HTTP::Headers{"Content-Type" => _ct || ""},
            body: _raw)),
      {% end %})
    end
    {% end %}

    # Delegate property access to the first component type.
    # TypeNode#instance_vars requires semantic phase and cannot be called during
    # module-scope macro expansion, so we use forward_missing_to instead.
    # Second-and-later type properties are accessible via their accessor getter.
    forward_missing_to @{{ types[0].id.underscore }}
  end
end
