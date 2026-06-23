module OpenAPI
  module Generator
    module Types
      # :nodoc:
      enum SchemaKind
        ScalarAlias    # named schema mapping to a primitive Crystal type or alias
        Enum           # string/integer with enum values → Crystal enum
        ExtensibleEnum # x-extensible-enum: known values + open string → value struct
        Struct         # small, flat, value-typed object
        Class          # complex or large object
        AbstractClass  # oneOf/anyOf with discriminator
        AnyAlias       # oneOf/anyOf — inline schemas present → JSON::Any alias
        UnionAlias     # oneOf/anyOf — all $refs, no discriminator → typed wrapper struct
        ComposeAlias   # allOf — all $refs (2+), no extras → delegate-based wrapper struct
        ArrayAlias     # top-level array schema → Array(T) alias
        Skip           # filtered out by hooks
        ErrorWrapper   # named response component wrapper: class Foo < Bar; end
      end
    end
  end
end
