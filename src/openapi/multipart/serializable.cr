require "http/formdata"
require "json"

module OpenAPI
  module Multipart
    annotation Field
    end

    # Generates `self.from_multipart` and `to_multipart` for any type that
    # includes it, mirroring the `JSON::Serializable` / `Form::Serializable` pattern.
    #
    # Scalar fields are sent as plain text parts. Binary fields (`IO::Memory`) are
    # sent as file parts. Nested types are JSON-encoded into a single text part
    # (the OpenAPI default when no `encoding.contentType` is specified for an object).
    #
    # Wire key resolution order:
    # 1. `@[OpenAPI::Multipart::Field(key: "...")]`
    # 2. `@[JSON::Field(key: "...")]`
    # 3. The Crystal instance variable name
    module Serializable
      macro included
        # Deserializes an instance of this type from a multipart/form-data HTTP request.
        # All parts are read into string or IO::Memory buckets first, then fields
        # are extracted by name. File parts (those with a filename) become IO::Memory.
        def self.from_multipart(request : HTTP::Request) : self
          {% verbatim do %}
          {% begin %}
          _parts = {} of String => String
          _files = {} of String => IO::Memory

          HTTP::FormData.parse(request) do |_part|
            _body = _part.body.gets_to_end
            if _part.filename
              _files[_part.name] = IO::Memory.new(_body)
            else
              _parts[_part.name] = _body
            end
          end

          new(
            {% for ivar in @type.instance_vars %}
              {% multi_ann = ivar.annotation(OpenAPI::Multipart::Field) %}
              {% json_ann = ivar.annotation(JSON::Field) %}
              {% base_key = (multi_ann && multi_ann[:key]) || (json_ann && json_ann[:key]) || ivar.name.stringify %}
              {% t = ivar.type %}
              {% nilable = t.nilable? %}
              {% if nilable %}
                {% core_t = t.union_types.reject { |u| u.name == "Nil" }.first %}
              {% else %}
                {% core_t = t %}
              {% end %}
              {{ ivar.name }}: (
                {% if core_t <= IO::Memory %}
                  if (_f = _files[{{ base_key }}]?)
                    _f
                  elsif (_s = _parts[{{ base_key }}]?)
                    IO::Memory.new(_s)
                  else
                    {% if nilable %}nil{% else %}IO::Memory.new{% end %}
                  end
                {% elsif core_t <= String %}
                  {% if nilable %}_parts[{{ base_key }}]?{% else %}_parts[{{ base_key }}]? || ""{% end %}
                {% elsif core_t <= Int32 %}
                  {% if nilable %}_parts[{{ base_key }}]?.try(&.to_i32){% else %}(_parts[{{ base_key }}]? || "0").to_i32{% end %}
                {% elsif core_t <= Int64 %}
                  {% if nilable %}_parts[{{ base_key }}]?.try(&.to_i64){% else %}(_parts[{{ base_key }}]? || "0").to_i64{% end %}
                {% elsif core_t <= Float32 %}
                  {% if nilable %}_parts[{{ base_key }}]?.try(&.to_f32){% else %}(_parts[{{ base_key }}]? || "0.0").to_f32{% end %}
                {% elsif core_t <= Float64 %}
                  {% if nilable %}_parts[{{ base_key }}]?.try(&.to_f64){% else %}(_parts[{{ base_key }}]? || "0.0").to_f64{% end %}
                {% elsif core_t <= Bool %}
                  {% if nilable %}_parts[{{ base_key }}]?.try { |_v| _v == "true" }{% else %}(_parts[{{ base_key }}]? == "true"){% end %}
                {% else %}
                  {% if nilable %}
                    _parts[{{ base_key }}]?.try { |_s| {{ core_t }}.from_json(_s) }
                  {% else %}
                    {{ core_t }}.from_json(_parts[{{ base_key }}]? || "{}")
                  {% end %}
                {% end %}
              ),
            {% end %}
          )
          {% end %}
          {% end %}
        end

        # Serializes this instance into a multipart form-data builder.
        def to_multipart(builder : HTTP::FormData::Builder) : Nil
          {% verbatim do %}
          {% begin %}
          {% for ivar in @type.instance_vars %}
            {% multi_ann = ivar.annotation(OpenAPI::Multipart::Field) %}
            {% json_ann = ivar.annotation(JSON::Field) %}
            {% base_key = (multi_ann && multi_ann[:key]) || (json_ann && json_ann[:key]) || ivar.name.stringify %}
            {% t = ivar.type %}
            {% nilable = t.nilable? %}
            {% if nilable %}
              {% core_t = t.union_types.reject { |u| u.name == "Nil" }.first %}
            {% else %}
              {% core_t = t %}
            {% end %}

            {% if core_t <= IO::Memory %}
              %io = @{{ ivar.name }}
              {% if nilable %}
                unless %io.nil?
                  builder.file({{ base_key }}, %io.not_nil!.rewind, HTTP::FormData::FileMetadata.new(filename: {{ base_key }}))
                end
              {% else %}
                builder.file({{ base_key }}, @{{ ivar.name }}.rewind, HTTP::FormData::FileMetadata.new(filename: {{ base_key }}))
              {% end %}
            {% elsif core_t <= String || core_t <= Int32 || core_t <= Int64 ||
                       core_t <= Float32 || core_t <= Float64 || core_t <= Bool %}
              %v = @{{ ivar.name }}
              {% if nilable %}
                unless %v.nil?
                  builder.field({{ base_key }}, %v.to_s)
                end
              {% else %}
                builder.field({{ base_key }}, @{{ ivar.name }}.to_s)
              {% end %}
            {% else %}
              %v = @{{ ivar.name }}
              {% if nilable %}
                unless %v.nil?
                  builder.field({{ base_key }}, %v.not_nil!.to_json)
                end
              {% else %}
                builder.field({{ base_key }}, @{{ ivar.name }}.to_json)
              {% end %}
            {% end %}
          {% end %}
          {% end %}
          {% end %}
        end
      end
    end
  end
end
