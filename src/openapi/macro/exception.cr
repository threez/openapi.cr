# Generates a typed exception class for OpenAPI error-response schemas.
#
# The block declares the Body struct members (getters + initialize).
# The macro wraps them in a `struct Body` with the requested format includes,
# and emits the thin `Exception` shell with delegation and format shims.
#
# Example:
#   openapi_exception ApiError do
#     getter code : Int32
#     getter message : String
#     def initialize(@code : Int32, @message : String); end
#   end
#
# Format args (all default false/nil — only pass what the generated file requires):
#   openapi_exception ApiError, yaml: true, xml: true do ... end
macro openapi_exception(name, json = true, yaml = false, xml = false, form = nil, multipart = false, &block)
  # Scan block for `getter message` to choose super(@body.message) vs super().
  {% has_message = false %}
  {% exprs = block.body.is_a?(Expressions) ? block.body.expressions : [block.body] %}
  {% for expr in exprs %}
    {% if expr.is_a?(Call) && expr.name == "getter" %}
      {% for arg in expr.args %}
        {% if arg.is_a?(TypeDeclaration) && arg.var.id.stringify == "message" %}
          {% has_message = true %}
        {% end %}
      {% end %}
    {% end %}
  {% end %}

  class {{name.id}} < ::Exception
    struct Body
      {% if json %}include ::JSON::Serializable{% end %}
      {% if yaml %}include ::YAML::Serializable{% end %}
      {% if xml %}include ::OpenAPI::XML::Serializable{% end %}
      {% if form %}include {{form.id}}{% end %}
      {% if multipart %}include ::OpenAPI::Multipart::Serializable{% end %}

      {{block.body}}
    end

    getter body : Body

    def initialize(@body : Body)
      {{has_message ? "super(@body.message)".id : "super()".id}}
    end

    forward_missing_to @body

    {% if json %}
    def self.from_json(input : String | IO) : self
      new(Body.from_json(input))
    end
    {% end %}

    {% if yaml %}
    def self.from_yaml(input : String | IO) : self
      new(Body.from_yaml(input))
    end
    {% end %}

    {% unless has_message %}
    def message : String?
      @body.inspect
    end
    {% end %}
  end
end
