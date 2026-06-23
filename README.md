# cryogen — Crystal code generator for OpenAPI 3.x

Generates idiomatic Crystal source code from an OpenAPI 3.x spec:

- **Types** — structs, classes, enums, and type aliases for every schema, with `JSON::Serializable` / `YAML::Serializable` included automatically
- **Client** — a typed `Client` class with one method per API operation
- **Server** — an abstract `Handler` for the [mux.cr](https://github.com/threez/mux.cr) router, or [Kemal](https://kemalcr.com/)

All output is passed through `crystal tool format` before being written.

## Installation

Add `cryogen` as a development dependency (it is a code-generation tool, not a runtime library):

```yaml
development_dependencies:
  openapi:
    github: threez/openapi.cr
```

Then:

```sh
shards install
shards build cryogen
```

## CLI usage

```
cryogen [options] <spec-file>
```

**Options**

- `--namespace NAME` — Crystal module wrapping all generated code (default: derived from filename, e.g. `petstore.yaml` → `Petstore`)
- `--output DIR` — output directory, created if absent (default: `.`)
- `--generators LIST` — comma-separated generators to run: `types`, `client`, `server`, `kemal` (default: `types,client,server`)
- `--formats LIST` — serialization mixins: `json`, `yaml` (default: `json,yaml`)
- `--custom-scalar MAPPING` — override a scalar type mapping, e.g. `string:decimal=BigDecimal` (repeatable)
- `--no-validate-params` — disable client-side parameter validation (see [Client](#client-clientcr))

**Examples**

```sh
# Generate everything from a local spec
cryogen petstore.yaml

# Choose namespace and output directory
cryogen petstore.yaml --namespace MyApi --output src/generated

# Types only, JSON serialization only
cryogen petstore.yaml --generators types --formats json

# Override scalar types
cryogen petstore.yaml \
  --custom-scalar string:ipv4=IPv4 \
  --custom-scalar string:ipv6=IPv6
```

## Generated output

### Types (`types.cr`)

Each OpenAPI schema component becomes the most appropriate Crystal construct:

- `type: object` with properties → `struct` (or `class` for inheritance / error types)
- `enum` → `openapi_enum` macro
- `x-extensible-enum` → `openapi_extensible_enum` macro
- `allOf` with one `$ref` → subclass
- `oneOf` / `anyOf` → `JSON::Any` alias
- Scalar with format → mapped type (e.g. `uuid` → `UUID`, `date-time` → `Time`)

Properties are nullable / optional / required as declared in the spec. Validation constraints (`minimum`, `maximum`, `minLength`, `maxLength`, `pattern`, `minItems`, `maxItems`) generate a `valid?` method via `OpenAPI::Validation::Helpers`.

### Client (`client.cr`)

```crystal
client = Petstore::Client.new(HTTP::Client.new("api.example.com"))
pet = client.show_pet_by_id(pet_id: "abc123")
```

Each operation becomes a typed method. Path parameters are interpolated; query and body parameters are keyword arguments.

When an operation has constrained parameters (`minimum`, `maximum`, `minLength`, `maxLength`, `pattern`, `enum`), the generated method validates them before sending the HTTP request and raises `OpenAPI::Validation::Exception` immediately on any violation:

```crystal
# Generated (petstore limit has maximum: 100)
def list_pets(limit : Int32? = nil) : Pets
  errors = [] of OpenAPI::Validation::Error
  if limit_val = limit
    validate_maximum errors, "limit", limit_val, 100_i32
  end
  raise OpenAPI::Validation::Exception.new(errors) unless errors.empty?
  # ... HTTP call ...
end
```

Pass `--no-validate-params` to the CLI (or `validate_params: false` to `RenderContext` / `Runner`) to generate a client without the validation block.

### Server (`server.cr` / `kemal_server.cr`)

```crystal
class MyHandler < Petstore::Handler
  def list_pets(env : HTTP::Server::Context, limit : Int32?) : Nil
    # implement
  end
end

handler = MyHandler.new
mux = Mux::Router.new
handler.register(mux)
```

The abstract `Handler` class declares one `abstract def` per operation. Subclass it and implement every operation. Use `--generators kemal` for a Kemal-compatible variant.

For operations with constrained parameters, the generated handler also provides a concrete `validate_{operation}_params` helper that returns any violations as `Array(OpenAPI::Validation::Error)`. The implementor decides what to do with them:

```crystal
def list_pets(limit : Int32? = nil) : Petstore::Pets
  errors = validate_list_pets_params(limit)
  raise Petstore::Error.new(code: 400, message: errors.first.message) unless errors.empty?
  # ... implementation ...
end
```

## Customisation via Hooks

Pass a `Hooks` subclass to override any part of the type-generation pipeline:

```crystal
class MyHooks < OpenAPI::Generator::Types::DefaultHooks
  # Map a custom OpenAPI type+format pair to a Crystal type.
  def format_type_for(openapi_type : String, format : String?) : String?
    "BigDecimal" if openapi_type == "number" && format == "decimal"
  end

  # Rename a schema to a different Crystal identifier.
  def crystal_name(openapi_name : String) : String
    openapi_name == "Error" ? "ApiError" : super
  end

  # Rename a property.
  def property_name(openapi_name : String) : String
    openapi_name == "type" ? "kind" : super
  end

  # Skip a schema entirely.
  def skip?(name : String, schema) : Bool
    name.starts_with?("Internal")
  end

  # Emit additional Crystal code after a generated type.
  def after_type(name : String, kind, b : Crystina::Builder) : Nil
    b.blank.comment("custom extension for #{name}")
  end
end

hooks = MyHooks.new
runner = OpenAPI::Generator::Runner.new(doc, "MyApi", "src/generated", Set{"json"}, hooks)
runner.run(%w[types client server])
```

The CLI exposes `--custom-scalar` as a convenience for `format_type_for` overrides. Programmatic use of `Runner` unlocks the full Hooks API.

## Built-in scalar mappings

Scalar types are mapped from OpenAPI `type`+`format` pairs to Crystal types. The defaults cover all standard JSON Schema formats:

- `string` → `String`; `date-time` / `date` → `Time`; `uuid` → `UUID`; `uri` / `uri-reference` → `URI`; `byte` → `Bytes`; `binary` → `IO`
- `integer` → `Int32`; `int64` / `unix-time` → `Int64`; `uint64` → `UInt64`
- `number` → `Float64`; `float` → `Float32`
- `boolean` → `Bool`

Use `--custom-scalar` (CLI) or `format_type_for` (Hooks) to add or override any mapping.

## Development

```sh
shards install   # fetches dev dependencies (mux.cr, kemal, crystina)
crystal spec     # runs the full test suite
shards build     # builds the cryogen binary
```

Specs live in `spec/`. Integration tests generate code from fixtures in `spec/fixtures/` and compare against golden files in `spec/integration/generated/`.

## Architecture decisions

Design rationale is documented in [`doc/adr/`](doc/adr/):

- [001](doc/adr/001-crystal-as-implementation-language.md) Crystal as implementation language
- [002](doc/adr/002-rich-typed-openapi-v3-model.md) Rich typed OpenAPI v3 model
- [003](doc/adr/003-three-part-generator-architecture.md) Generator architecture
- [004](doc/adr/004-extensible-generator-architecture.md) Extensible generator architecture
- [005](doc/adr/005-crystina-builder-dsl.md) Crystina builder DSL (code generation strategy)
- [006](doc/adr/006-scalar-type-override-via-hooks.md) Scalar type override via Hooks
- [007](doc/adr/007-ref-resolution-strategy.md) `$ref` resolution strategy
- [008](doc/adr/008-redocly-extensions-for-type-generation.md) Redocly extensions for type generation
- [009](doc/adr/009-extensible-enum-type-generation.md) Extensible enum type generation
- [010](doc/adr/010-runtime-validation-for-generated-types.md) Runtime validation for generated types

## Contributing

1. Fork it (<https://github.com/threez/openapi.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Vincent Landgraf](https://github.com/threez) — creator and maintainer

## License

MIT
