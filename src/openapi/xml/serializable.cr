require "xml"

module OpenAPI
  module XML
    # Optional annotation to customize XML serialization for a field.
    # Falls back to `@[JSON::Field(key:)]`, then the Crystal instance variable name.
    #
    # Parameters:
    #   key:      element/attribute name override
    #   attribute: serialize as XML attribute instead of a child element
    #   wrapped:  wrap array items in an outer element named by `key`
    #   item_key: element name for each item when the field is an array of scalars
    annotation Field
    end

    # Type-level annotation to override the root XML element name for a class or struct.
    annotation Element
    end

    # Adds `to_xml`, `from_xml`, `_append_xml`, and `_from_xml_node` to any Crystal
    # class or struct.  Mirrors the `JSON::Serializable` / `YAML::Serializable` pattern.
    #
    # Element name resolution for a type:
    # 1. `@[OpenAPI::XML::Element(name: "...")]` on the class/struct
    # 2. Unqualified class name, downcased  (e.g. `Petstore::Pet` → `"pet"`)
    #
    # Field name resolution (element name or attribute name):
    # 1. `@[OpenAPI::XML::Field(key: "...")]`
    # 2. `@[JSON::Field(key: "...")]`
    # 3. Crystal instance variable name
    module Serializable
      macro included
        # Returns the XML element name for this type.
        def self.xml_element_name : String
          {% ann = @type.annotation(OpenAPI::XML::Element) %}
          {% if ann && ann[:name] %}
            {{ ann[:name] }}
          {% else %}
            {{ @type.name.split("::").last.downcase }}
          {% end %}
        end

        # Appends this object as a child XML element to *xml*.
        # Attribute fields are emitted first (XML requirement), then child elements.
        def _append_xml(xml : ::XML::Builder, name : String = self.class.xml_element_name) : Nil
          xml.element(name) do
            {% verbatim do %}
            {% begin %}

            # ── Pass 1: XML attributes ────────────────────────────────────
            {% for ivar in @type.instance_vars %}
              {% xml_ann = ivar.annotation(OpenAPI::XML::Field) %}
              {% if xml_ann && xml_ann[:attribute] %}
                {% json_ann = ivar.annotation(JSON::Field) %}
                {% key = (xml_ann && xml_ann[:key]) || (json_ann && json_ann[:key]) || ivar.name.stringify %}
                {% nilable = ivar.type.nilable? %}

                {% if nilable %}
                  @{{ ivar.name }}.try { |_v| xml.attribute({{ key }}, _v.to_s) }
                {% else %}
                  xml.attribute({{ key }}, @{{ ivar.name }}.to_s)
                {% end %}
              {% end %}
            {% end %}

            # ── Pass 2: child elements ────────────────────────────────────
            {% for ivar in @type.instance_vars %}
              {% xml_ann = ivar.annotation(OpenAPI::XML::Field) %}
              {% unless xml_ann && xml_ann[:attribute] %}

              {% json_ann = ivar.annotation(JSON::Field) %}
              {% key = (xml_ann && xml_ann[:key]) || (json_ann && json_ann[:key]) || ivar.name.stringify %}
              {% nilable = ivar.type.nilable? %}
              {% core_t = nilable ? ivar.type.union_types.reject { |u| u == Nil }.first : ivar.type %}
              {% is_wrapped = xml_ann && xml_ann[:wrapped] %}

              {% if core_t <= OpenAPI::XML::Serializable %}
                # ── Nested serializable ──────────────────────────────────
                {% if nilable %}
                  @{{ ivar.name }}.try { |_xv| _xv._append_xml(xml, {{ key }}) }
                {% else %}
                  @{{ ivar.name }}._append_xml(xml, {{ key }})
                {% end %}

              {% elsif core_t.name.starts_with?("Array") %}
                # ── Array field ──────────────────────────────────────────
                {% item_type = core_t.type_vars[0] %}
                {% item_key = (xml_ann && xml_ann[:item_key]) || ivar.name.stringify %}

                {% if is_wrapped %}
                  {% if nilable %}
                    @{{ ivar.name }}.try do |_arr|
                      xml.element({{ key }}) do
                        _arr.each do |_e|
                          {% if item_type <= OpenAPI::XML::Serializable %}
                            _e._append_xml(xml)
                          {% else %}
                            xml.element({{ item_key }}) { xml.text _e.to_s }
                          {% end %}
                        end
                      end
                    end
                  {% else %}
                    xml.element({{ key }}) do
                      @{{ ivar.name }}.each do |_e|
                        {% if item_type <= OpenAPI::XML::Serializable %}
                          _e._append_xml(xml)
                        {% else %}
                          xml.element({{ item_key }}) { xml.text _e.to_s }
                        {% end %}
                      end
                    end
                  {% end %}
                {% else %}
                  # Unwrapped — emit items directly, no outer wrapper
                  {% if nilable %}
                    @{{ ivar.name }}.try do |_arr|
                      _arr.each do |_e|
                        {% if item_type <= OpenAPI::XML::Serializable %}
                          _e._append_xml(xml)
                        {% else %}
                          xml.element({{ item_key }}) { xml.text _e.to_s }
                        {% end %}
                      end
                    end
                  {% else %}
                    @{{ ivar.name }}.each do |_e|
                      {% if item_type <= OpenAPI::XML::Serializable %}
                        _e._append_xml(xml)
                      {% else %}
                        xml.element({{ item_key }}) { xml.text _e.to_s }
                      {% end %}
                    end
                  {% end %}
                {% end %}

              {% else %}
                # ── Scalar element ───────────────────────────────────────
                {% if nilable %}
                  unless @{{ ivar.name }}.nil?
                    xml.element({{ key }}) { xml.text @{{ ivar.name }}.not_nil!.to_s }
                  end
                {% else %}
                  xml.element({{ key }}) { xml.text @{{ ivar.name }}.to_s }
                {% end %}
              {% end %}
              {% end %} # end unless attribute
            {% end %}

            {% end %}
            {% end %}
          end
        end

        def to_xml : String
          ::XML.build(indent: "  ") { |xml| _append_xml(xml) }
        end

        def self._from_xml_node(node : ::XML::Node) : self
          {% verbatim do %}
          {% begin %}
          new(
            {% for ivar in @type.instance_vars %}
              {% xml_ann = ivar.annotation(OpenAPI::XML::Field) %}
              {% json_ann = ivar.annotation(JSON::Field) %}
              {% key = (xml_ann && xml_ann[:key]) || (json_ann && json_ann[:key]) || ivar.name.stringify %}
              {% nilable = ivar.type.nilable? %}
              {% core_t = nilable ? ivar.type.union_types.reject { |u| u == Nil }.first : ivar.type %}
              {% is_attr = xml_ann && xml_ann[:attribute] %}
              {% is_wrapped = xml_ann && xml_ann[:wrapped] %}

              {{ ivar.name }}: (begin
                {% if is_attr %}
                  # ── Read from XML attribute ──────────────────────────
                  _attr_text = node[{{ key }}]?
                  {% if nilable %}
                    _attr_text.try { |_v|
                      {% if core_t == String %}  _v
                      {% elsif core_t == Int32 %} _v.to_i32
                      {% elsif core_t == Int64 %} _v.to_i64
                      {% elsif core_t == Float32 %} _v.to_f32
                      {% elsif core_t == Float64 %} _v.to_f64
                      {% elsif core_t == Bool %}  _v == "true"
                      {% else %} nil
                      {% end %}
                    }
                  {% else %}
                    _v = _attr_text.not_nil!
                    {% if core_t == String %}  _v
                    {% elsif core_t == Int32 %} _v.to_i32
                    {% elsif core_t == Int64 %} _v.to_i64
                    {% elsif core_t == Float32 %} _v.to_f32
                    {% elsif core_t == Float64 %} _v.to_f64
                    {% elsif core_t == Bool %}  _v == "true"
                    {% else %} {{ core_t }}.new
                    {% end %}
                  {% end %}

                {% elsif core_t.name.starts_with?("Array") %}
                  # ── Array field ──────────────────────────────────────
                  {% item_type = core_t.type_vars[0] %}
                  {% item_key = (xml_ann && xml_ann[:item_key]) || ivar.name.stringify %}

                  {% if is_wrapped %}
                    _wrapper = node.children.find { |_n| _n.element? && _n.name == {{ key }} }
                    _item_src = _wrapper || node
                    {% if item_type <= OpenAPI::XML::Serializable %}
                      _arr_items = _item_src.children.select(&.element?).map { |_item_node|
                        {{ item_type }}._from_xml_node(_item_node)
                      }
                    {% else %}
                      _arr_items = _item_src.children
                        .select { |_n| _n.element? && _n.name == {{ item_key }} }
                        .map { |_item_node|
                          {% if item_type == String %}  _item_node.content
                          {% elsif item_type == Int32 %}   _item_node.content.to_i32
                          {% elsif item_type == Int64 %}   _item_node.content.to_i64
                          {% elsif item_type == Float32 %}  _item_node.content.to_f32
                          {% elsif item_type == Float64 %}  _item_node.content.to_f64
                          {% elsif item_type == Bool %}    _item_node.content == "true"
                          {% else %} _item_node.content
                          {% end %}
                        }
                    {% end %}
                    {% if nilable %}
                      _wrapper.nil? && _arr_items.empty? ? nil : _arr_items
                    {% else %}
                      _arr_items
                    {% end %}
                  {% else %}
                    # Unwrapped — items are direct children of node
                    {% if item_type <= OpenAPI::XML::Serializable %}
                      _arr_items = node.children.select { |_n|
                        _n.element? && _n.name == {{ item_type }}.xml_element_name
                      }.map { |_item_node|
                        {{ item_type }}._from_xml_node(_item_node)
                      }
                    {% else %}
                      _arr_items = node.children
                        .select { |_n| _n.element? && _n.name == {{ item_key }} }
                        .map { |_item_node|
                          {% if item_type == String %}  _item_node.content
                          {% elsif item_type == Int32 %}   _item_node.content.to_i32
                          {% elsif item_type == Int64 %}   _item_node.content.to_i64
                          {% elsif item_type == Float32 %}  _item_node.content.to_f32
                          {% elsif item_type == Float64 %}  _item_node.content.to_f64
                          {% elsif item_type == Bool %}    _item_node.content == "true"
                          {% else %} _item_node.content
                          {% end %}
                        }
                    {% end %}
                    {% if nilable %}
                      _arr_items.empty? ? nil : _arr_items
                    {% else %}
                      _arr_items
                    {% end %}
                  {% end %}

                {% elsif core_t <= OpenAPI::XML::Serializable %}
                  # ── Nested serializable ──────────────────────────────
                  _child = node.children.find { |_n| _n.element? && _n.name == {{ key }} }
                  {% if nilable %}
                    _child.try { |_nc| {{ core_t }}._from_xml_node(_nc) }
                  {% else %}
                    {{ core_t }}._from_xml_node(_child.not_nil!)
                  {% end %}

                {% else %}
                  # ── Scalar element ───────────────────────────────────
                  _text = node.children.find { |_n| _n.element? && _n.name == {{ key }} }.try(&.content)
                  {% if core_t == String %}
                    {% if nilable %} _text {% else %} _text.not_nil! {% end %}
                  {% elsif core_t == Int32 %}
                    {% if nilable %} _text.try(&.to_i32) {% else %} _text.not_nil!.to_i32 {% end %}
                  {% elsif core_t == Int64 %}
                    {% if nilable %} _text.try(&.to_i64) {% else %} _text.not_nil!.to_i64 {% end %}
                  {% elsif core_t == Float32 %}
                    {% if nilable %} _text.try(&.to_f32) {% else %} _text.not_nil!.to_f32 {% end %}
                  {% elsif core_t == Float64 %}
                    {% if nilable %} _text.try(&.to_f64) {% else %} _text.not_nil!.to_f64 {% end %}
                  {% elsif core_t == Bool %}
                    {% if nilable %} _text.try { |_v| _v == "true" } {% else %} _text.not_nil! == "true" {% end %}
                  {% else %}
                    {% if nilable %} nil {% else %} {{ core_t }}.new {% end %}
                  {% end %}
                {% end %}
              end),
            {% end %}
          )
          {% end %}
          {% end %}
        end

        def self.from_xml(input : String | IO) : self
          raw = input.is_a?(IO) ? input.gets_to_end : input
          doc = ::XML.parse(raw)
          root = doc.first_element_child.not_nil!
          _from_xml_node(root)
        end
      end
    end
  end
end

class Array(T)
  def to_xml : String
    ::XML.build(indent: "  ") do |xml|
      xml.element(T.xml_element_name + "s") do
        each(&._append_xml(xml))
      end
    end
  end

  def self.from_xml(input : String | IO) : self
    raw = input.is_a?(IO) ? input.gets_to_end : input
    doc = ::XML.parse(raw)
    if root = doc.first_element_child
      root.children.select(&.element?).map { |child| T._from_xml_node(child) }
    else
      raise NilAssertionError.new
    end
  end
end
