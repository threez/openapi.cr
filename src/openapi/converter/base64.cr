require "base64"

module OpenAPI
  module Converter
    # JSON converter for OpenAPI `format: byte` fields (base64-encoded binary).
    # Use with `@[JSON::Field(converter: OpenAPI::Converter::Base64)]`.
    module Base64
      def self.from_json(pull : JSON::PullParser) : Bytes
        ::Base64.decode(pull.read_string)
      end

      def self.to_json(value : Bytes, builder : JSON::Builder) : Nil
        builder.string(::Base64.strict_encode(value))
      end
    end
  end
end
