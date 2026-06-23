module OpenAPI
  module Generator
    module Types
      # :nodoc:
      module TypeMapper
        SCALAR_MAP = {
          # String types — officially defined OpenAPI/JSON Schema formats
          {"string", nil}         => "String",
          {"string", "date-time"} => "Time",
          {"string", "date"}      => "Time",
          # "time" (time-only, e.g. "14:30:00") maps to String because Crystal's
          # Time.from_json expects RFC 3339 and cannot parse a time-only value.
          {"string", "time"}          => "String",
          {"string", "uuid"}          => "UUID",
          {"string", "uri"}           => "URI",
          {"string", "uri-reference"} => "URI",
          {"string", "byte"}          => "Bytes",
          {"string", "binary"}        => "IO::Memory",
          {"string", "email"}         => "String",
          {"string", "idn-email"}     => "String",
          {"string", "hostname"}      => "String",
          {"string", "idn-hostname"}  => "String",
          # ipv4/ipv6 map to String rather than Socket::IPAddress because
          # Socket::IPAddress does not include JSON::Serializable.
          {"string", "ipv4"} => "String",
          {"string", "ipv6"} => "String",
          # cidr/decimal/duration/password/regex/json-pointer: no stdlib type.
          # decimal in practice is always string-typed (e.g. Stripe stores "1.50").
          # BigDecimal would require an external shard and is not mapped here.
          {"string", "cidr"}         => "String",
          {"string", "decimal"}      => "String",
          {"string", "duration"}     => "String",
          {"string", "password"}     => "String",
          {"string", "regex"}        => "String",
          {"string", "json-pointer"} => "String",
          # Integer types
          {"integer", nil}     => "Int32",
          {"integer", "int32"} => "Int32",
          {"integer", "int64"} => "Int64",
          # uint64 is used by Google APIs; must not fall back to Int32.
          {"integer", "uint64"} => "UInt64",
          # unix-time is seconds since epoch; Int64 avoids the 2038 overflow.
          {"integer", "unix-time"} => "Int64",
          # Number types
          {"number", nil}      => "Float64",
          {"number", "float"}  => "Float32",
          {"number", "double"} => "Float64",
          # Boolean
          {"boolean", nil} => "Bool",
        }

        JSON_CAST_MAP = {
          "Int32"   => ".as_i.to_i32",
          "Int64"   => ".as_i.to_i64",
          "UInt64"  => ".as_i.to_u64",
          "Float32" => ".as_f.to_f32",
          "Float64" => ".as_f",
          "Bool"    => ".as_bool",
        }

        def self.json_parse_accessor(type_str : String, prop_name : String, required : Bool) : String
          key = prop_name.inspect
          base = type_str.rchop('?')
          nullable = type_str.ends_with?('?') || !required
          fetch = nullable ? "parsed[#{key}]?" : "parsed[#{key}]"
          converter = JSON_CAST_MAP[base]? || ".as_s"
          nullable ? "#{fetch}.try(&#{converter})" : "#{fetch}#{converter}"
        end

        def self.crystal_type(schema : Model::Schema) : String
          if ref = schema.ref
            ref_name(ref)
          elsif schema.type == "array"
            item_type = if items = schema.items
                          if ref = items.ref
                            ref_name(ref)
                          elsif s = items.value
                            crystal_type(s)
                          else
                            "JSON::Any"
                          end
                        else
                          "JSON::Any"
                        end
            "Array(#{item_type})"
          elsif ht = additional_properties_hash_type(schema)
            ht
          else
            SCALAR_MAP[{schema.type, schema.format}]? ||
              SCALAR_MAP[{schema.type, nil}]? ||
              "JSON::Any"
          end
        end

        # Returns "Hash(String, T)" when the schema is a pure additionalProperties
        # map (no regular properties), nil otherwise.
        def self.additional_properties_hash_type(schema : Model::Schema) : String?
          return nil unless schema.properties.nil? || schema.properties.try(&.empty?)
          ap = schema.additional_properties || return nil
          ap_schema = ap.schema || return nil
          val_type = if ref = ap_schema.ref
                       ref_name(ref)
                     elsif s = ap_schema.value
                       SCALAR_MAP[{s.type, s.format}]? || SCALAR_MAP[{s.type, nil}]? || "JSON::Any"
                     else
                       return nil
                     end
          "Hash(String, #{val_type})"
        end

        def self.ref_name(ref : String) : String
          name = ref.split("/").last
          return name if name.empty?
          # PascalCase each dot-separated word: "apps.secret" → "AppsSecret",
          # "treasury.credit_reversal" → "TreasuryCreditReversal".
          name.split('.').map { |part| NameInflector.pascal_case(part) }.join
        end

        def self.scalar?(schema : Model::Schema) : Bool
          !!(SCALAR_MAP[{schema.type, schema.format}]? || SCALAR_MAP[{schema.type, nil}]?)
        end

        # Returns true when the schema is a string-valued enum (not bool, not integer).
        # These are promoted to typed Crystal enums; runtime `validate_enum` is skipped.
        def self.string_enum?(schema : Model::Schema) : Bool
          vals = schema.enum_values.try(&.as_a?) || return false
          return false if vals.empty?
          return false if vals.all? { |v| !v.as_bool?.nil? }
          !vals.first.as_s?.nil?
        end
      end
    end
  end
end
