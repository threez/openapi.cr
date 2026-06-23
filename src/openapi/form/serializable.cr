require "http/params"

module OpenAPI
  module Form
    annotation Field
    end

    # Generates `self.from_form_params` and `to_form_params` for any type that
    # includes it, mirroring the `JSON::Serializable` / `YAML::Serializable` pattern.
    #
    # Supports nested objects and arrays using Rails bracket notation:
    #   - Scalars:                     `name=Alice`
    #   - Nested Form::Serializable:   `address[city]=SF&address[zip]=94105`
    #   - Array of scalars:            `tags[]=ruby&tags[]=rails`
    #   - Array of Form::Serializable: `items[0][name]=X&items[1][name]=Y`
    #
    # The wire key for each property is resolved in order:
    # 1. `@[OpenAPI::Form::Field(key: "...")]`
    # 2. `@[JSON::Field(key: "...")]` (keeps form keys consistent with JSON)
    # 3. The Crystal instance variable name
    module Serializable
      # Builds a nested bracket key: `prefix[field]` when prefix is set, `field` otherwise.
      def self.build_key(prefix : String?, field : String) : String
        prefix ? "#{prefix}[#{field}]" : field
      end

      macro included
        # Deserializes an instance of this type from URL-encoded form params.
        # An optional *prefix* scopes all key lookups (e.g. `"address"` → `address[city]`).
        def self.from_form_params(params : HTTP::Params, prefix : String? = nil) : self
          {% verbatim do %}
          {% begin %}
          new(
            {% for ivar in @type.instance_vars %}
              {% t = ivar.type %}
              {% form_ann = ivar.annotation(OpenAPI::Form::Field) %}
              {% json_ann = ivar.annotation(JSON::Field) %}
              {% base_key = (form_ann && form_ann[:key]) || (json_ann && json_ann[:key]) || ivar.name.stringify %}
              {% nilable = t.nilable? %}

              {% if t <= Array(String) || t <= Array(String)? %}
                {{ ivar.name }}: begin
                  _k = OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})
                  _vals = params.fetch_all(_k + "[]")
                  {% if nilable %}_vals.empty? ? nil : _vals{% else %}_vals{% end %}
                end,
              {% elsif t <= Array(Int32) || t <= Array(Int32)? %}
                {{ ivar.name }}: begin
                  _k = OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})
                  _vals = params.fetch_all(_k + "[]").map(&.to_i32)
                  {% if nilable %}_vals.empty? ? nil : _vals{% else %}_vals{% end %}
                end,
              {% elsif t <= Array(Int64) || t <= Array(Int64)? %}
                {{ ivar.name }}: begin
                  _k = OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})
                  _vals = params.fetch_all(_k + "[]").map(&.to_i64)
                  {% if nilable %}_vals.empty? ? nil : _vals{% else %}_vals{% end %}
                end,
              {% elsif t <= Array(Float64) || t <= Array(Float64)? %}
                {{ ivar.name }}: begin
                  _k = OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})
                  _vals = params.fetch_all(_k + "[]").map(&.to_f64)
                  {% if nilable %}_vals.empty? ? nil : _vals{% else %}_vals{% end %}
                end,
              {% elsif t <= Array(Float32) || t <= Array(Float32)? %}
                {{ ivar.name }}: begin
                  _k = OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})
                  _vals = params.fetch_all(_k + "[]").map(&.to_f32)
                  {% if nilable %}_vals.empty? ? nil : _vals{% else %}_vals{% end %}
                end,
              {% elsif t <= Array(Bool) || t <= Array(Bool)? %}
                {{ ivar.name }}: begin
                  _k = OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})
                  _vals = params.fetch_all(_k + "[]").map { |_v| _v == "true" }
                  {% if nilable %}_vals.empty? ? nil : _vals{% else %}_vals{% end %}
                end,
              {% elsif t <= OpenAPI::Form::Serializable || t <= OpenAPI::Form::Serializable? %}
                {% inner_t = nilable ? t.union_types.reject { |u| u.name == "Nil" }.first : t %}
                {% _fk = "OpenAPI::Form::Serializable.build_key(prefix, #{base_key})" %}
                {{ ivar.name }}: {% if nilable %}(begin
                  _nk = {{ _fk.id }} + "["
                  _present = false
                  params.each { |_k, _| _present = true if _k.starts_with?(_nk) }
                  _present ? {{ inner_t }}.from_form_params(params, {{ _fk.id }}) : nil
                end){% else %}{{ inner_t }}.from_form_params(params, {{ _fk.id }}){% end %},
              {% elsif t <= Int32? %}
                {{ ivar.name }}: {% if nilable %}params[OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})]?.try(&.to_i32){% else %}params[OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})].to_i32{% end %},
              {% elsif t <= Int64? %}
                {{ ivar.name }}: {% if nilable %}params[OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})]?.try(&.to_i64){% else %}params[OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})].to_i64{% end %},
              {% elsif t <= Float32? %}
                {{ ivar.name }}: {% if nilable %}params[OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})]?.try(&.to_f32){% else %}params[OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})].to_f32{% end %},
              {% elsif t <= Float64? %}
                {{ ivar.name }}: {% if nilable %}params[OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})]?.try(&.to_f64){% else %}params[OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})].to_f64{% end %},
              {% elsif t <= Bool? %}
                {{ ivar.name }}: {% if nilable %}params[OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})]?.try { |_v| _v == "true" }{% else %}params[OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})]? == "true"{% end %},
              {% elsif t <= String? %}
                {{ ivar.name }}: {% if nilable %}params[OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})]?{% else %}params[OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})]{% end %},
              {% elsif t <= UUID || (t.nilable? && t.union_types.reject { |u| u.name == "Nil" }.first <= UUID) %}
                {{ ivar.name }}: {% if nilable %}params[OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})]?.try { |_v| UUID.new(_v) }{% else %}UUID.new(params[OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})]){% end %},
              {% elsif (nilable ? t.union_types.reject { |u| u.name == "Nil" }.first <= Enum : t <= Enum) %}
                {% inner_t = nilable ? t.union_types.reject { |u| u.name == "Nil" }.first : t %}
                {{ ivar.name }}: {% if nilable %}params[OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})]?.try { |_v| {{ inner_t }}.from_wire(_v) }{% else %}{{ inner_t }}.from_wire(params[OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})]){% end %},
              {% else %}
                # Unsupported type (e.g. Array of Form::Serializable): emit empty collection or nil.
                # Indexed-array deserialization is not supported; construct objects in Crystal directly.
                {{ ivar.name }}: {% if nilable %}nil{% else %}{{ t }}.new{% end %},
              {% end %}
            {% end %}
          )
          {% end %}
          {% end %}
        end

        # Serializes this instance to a URL-encoded form params string.
        def to_form_params : String
          HTTP::Params.build { |_p| _form_append(_p, nil) }
        end

        # Appends all fields to *p* using Rails bracket notation under *prefix*.
        # Called recursively for nested Form::Serializable objects.
        def _form_append(p : HTTP::Params::Builder, prefix : String?) : Nil
          {% verbatim do %}
          {% begin %}
          {% for ivar in @type.instance_vars %}
            {% t = ivar.type %}
            {% form_ann = ivar.annotation(OpenAPI::Form::Field) %}
            {% json_ann = ivar.annotation(JSON::Field) %}
            {% base_key = (form_ann && form_ann[:key]) || (json_ann && json_ann[:key]) || ivar.name.stringify %}
            {% nilable = t.nilable? %}

            {% if t <= Array(String) || t <= Array(String)? ||
                    t <= Array(Int32) || t <= Array(Int32)? ||
                    t <= Array(Int64) || t <= Array(Int64)? ||
                    t <= Array(Float32) || t <= Array(Float32)? ||
                    t <= Array(Float64) || t <= Array(Float64)? ||
                    t <= Array(Bool) || t <= Array(Bool)? %}
              %arr = @{{ ivar.name }}
              {% if nilable %}
                unless %arr.nil?
                  %k = OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})
                  %arr.not_nil!.each { |e| p.add(%k + "[]", e.to_s) }
                end
              {% else %}
                %k = OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})
                %arr.each { |e| p.add(%k + "[]", e.to_s) }
              {% end %}
            {% elsif t <= OpenAPI::Form::Serializable || t <= OpenAPI::Form::Serializable? %}
              %v = @{{ ivar.name }}
              {% if nilable %}
                unless %v.nil?
                  %v.not_nil!._form_append(p, OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }}))
                end
              {% else %}
                %v._form_append(p, OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }}))
              {% end %}
            {% elsif t <= UUID || (t.nilable? && t.union_types.reject { |u| u.name == "Nil" }.first <= UUID) %}
              %v = @{{ ivar.name }}
              {% if nilable %}
                unless %v.nil?
                  p.add(OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }}), %v.to_s)
                end
              {% else %}
                p.add(OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }}), %v.to_s)
              {% end %}
            {% elsif t <= String? || t <= Int32? || t <= Int64? || t <= Float32? || t <= Float64? || t <= Bool? %}
              %v = @{{ ivar.name }}
              {% if nilable %}
                unless %v.nil?
                  p.add(OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }}), %v.to_s)
                end
              {% else %}
                p.add(OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }}), %v.to_s)
              {% end %}
            {% elsif (nilable ? t.union_types.reject { |u| u.name == "Nil" }.first <= Enum : t <= Enum) %}
              %v = @{{ ivar.name }}
              {% if nilable %}
                unless %v.nil?
                  p.add(OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }}), %v.wire_value)
                end
              {% else %}
                p.add(OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }}), %v.wire_value)
              {% end %}
            {% else %}
              # Remaining: Array(Form::Serializable) or Array(Enum/other scalar-like).
              # Non-array types (Time, Bytes, UInt64, etc.) are skipped — unsupported.
              {% core_e = nilable ? t.union_types.reject { |u| u.name == "Nil" }.first : t %}
              {% elem_t = core_e.type_vars.first %}
              {% if elem_t %}
              %arr2 = @{{ ivar.name }}
              {% if nilable %}
                unless %arr2.nil?
                  %k2 = OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})
                  {% if elem_t <= OpenAPI::Form::Serializable %}
                    %arr2.not_nil!.each_with_index { |e, i| e._form_append(p, "#{%k2}[#{i}]") }
                  {% elsif elem_t <= Enum %}
                    %arr2.not_nil!.each { |e| p.add(%k2 + "[]", e.wire_value) }
                  {% else %}
                    %arr2.not_nil!.each { |e| p.add(%k2 + "[]", e.to_s) }
                  {% end %}
                end
              {% else %}
                %k2 = OpenAPI::Form::Serializable.build_key(prefix, {{ base_key }})
                {% if elem_t <= OpenAPI::Form::Serializable %}
                  %arr2.each_with_index { |e, i| e._form_append(p, "#{%k2}[#{i}]") }
                {% elsif elem_t <= Enum %}
                  %arr2.each { |e| p.add(%k2 + "[]", e.wire_value) }
                {% else %}
                  %arr2.each { |e| p.add(%k2 + "[]", e.to_s) }
                {% end %}
              {% end %}
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
