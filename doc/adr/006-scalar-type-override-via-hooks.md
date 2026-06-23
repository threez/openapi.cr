# ADR-006: Scalar Type Override via Hooks

**Status:** Accepted  
**Date:** 2026-06-20  
**Updated:** 2026-06-21

## Context

OpenAPI's scalar type system (`type: string`, `format: ipv4`, etc.) does not map
cleanly to every project's Crystal types. A project might use a custom `IPv4` struct
instead of `String` for `format: ipv4`, or `BigDecimal` instead of `Float64` for
`format: decimal`. Hard-coding these mappings would force forks; ignoring them would
produce types that require manual post-processing after every generation run.

The generator needs a sanctioned extension point for scalar type overrides that works
both programmatically and from the CLI.

## Decision

`TypesGenerator` accepts an optional `Hooks` instance. `Hooks` is an abstract class
with no-op defaults; callers override only what they need:

```crystal
abstract class OpenAPI::Generator::Types::Hooks
  # Return a Crystal type string for an OpenAPI type+format pair,
  # or nil to fall through to the built-in SCALAR_MAP.
  def format_type_for(openapi_type : String, format : String?) : String?
    nil
  end

  # Further extension points: crystal_type_for, classify, skip?, crystal_name,
  # property_name, after_type.
end
```

The built-in `SCALAR_MAP` in `TypeMapper` defines the default mappings for all
standard OpenAPI formats. `format_type_for` is consulted first; a non-nil return
short-circuits the map lookup.

### Programmatic use

```crystal
class MyHooks < OpenAPI::Generator::Types::DefaultHooks
  def format_type_for(openapi_type, format)
    case {openapi_type, format}
    when {"string", "ipv4"}    then "IPv4"
    when {"string", "decimal"} then "BigDecimal"
    end
  end
end

runner = OpenAPI::Generator::Runner.new(doc, ..., hooks: MyHooks.new)
```

### CLI use

The `cryogen` binary exposes the same capability via `--custom-scalar`, which is
repeatable and parsed into a `CLIHooks` instance at startup:

```
cryogen petstore.yaml \
  --custom-scalar string:ipv4=IPv4 \
  --custom-scalar string:decimal=BigDecimal \
  --custom-scalar number=Float32
```

The format is `<openapi-type>:<format>=<CrystalType>`. Omitting `:<format>` matches
any format for that type (equivalent to `format: nil` in the hook).

### Scope

Scalar overrides affect only `TypesGenerator` — the types file is where Crystal type
names are defined. `ClientGenerator` and `ServerGenerator` reference those names via
`$ref`, so they pick up the change automatically once the types file is regenerated.

## Consequences

- **Positive**: No fork required to customise scalar mappings — the extension point
  is part of the public API.
- **Positive**: The CLI `--custom-scalar` flag makes one-off overrides accessible
  without writing any Crystal code.
- **Positive**: `Hooks` covers more than scalars — name inflection, schema skipping,
  and post-type emission are all overridable in code, giving programmatic users full
  control.
- **Negative**: `Hooks` only applies to `TypesGenerator`. A project that also needs
  to customise client or server output must subclass those generators directly.
