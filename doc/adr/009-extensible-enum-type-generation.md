# ADR 009 — Extensible Enum Type Generation via x-extensible-enum

## Status

Accepted

## Context

OpenAPI's `enum` keyword defines a closed set of values — any value outside the set is invalid.
In practice, many APIs publish a *best-effort* list of known values while explicitly allowing
additional values to appear in responses as the API evolves. Redocly documents this pattern with
the `x-extensible-enum` extension: a field annotated with `x-extensible-enum` accepts the listed
values *and* any other value of the base type (usually `string`).

Real-world specs that use this extension include:
- **IONOS Cloud v6** — `licenceType`, `ApplicationType`, GPU `type` (7 occurrences)
- **IONOS NFS v1** — `sizeUnit` (TiB | GiB | …), `minVersion` (NFS protocol versions)

Before this ADR the generator silently discarded the `x-extensible-enum` list and classified
these schemas as plain `ScalarAlias` (e.g. `alias LicenceType = String`). The known values were
lost, and any `default` referencing a value produced an invalid Crystal string literal instead of
a typed constant.

A second gap, addressed together: when a property `$ref`s an enum or extensible-enum type and
carries a `default` value, `crystal_literal` previously returned the raw wire string
(`"\"TiB\""`) rather than the correct Crystal constant reference (`SizeUnit::TIB`).

## Decision

### 1. New `SchemaKind::ExtensibleEnum`

A dedicated kind separates extensible enums from both `Enum` (closed, Crystal `enum`) and
`ScalarAlias` (opaque alias). The collector classifies any schema that has `x-extensible-enum`
as `ExtensibleEnum` before reaching the scalar or object checks.

### 2. Value-struct representation

Neither a Crystal `enum` (closed type) nor a plain `alias = String` (no type safety) fits the
semantics. A `SomeType | String` union has a JSON parsing hazard — once
`JSON::PullParser#read_string` is called and raises, the parser position cannot be rewound for
the fallback branch.

The chosen representation is a **value struct** that wraps a `String`:

```crystal
# Extensible: known values or any String
struct SizeUnit
  TIB = new("TiB")
  GIB = new("GiB")

  getter value : String

  def initialize(@value : String)
  end

  def self.from_json(pull : JSON::PullParser) : self
    new(pull.read_string)
  end

  def to_json(builder : JSON::Builder)
    @value.to_json(builder)
  end

  def self.new(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : self
    node.raise "Expected scalar" unless node.is_a?(YAML::Nodes::Scalar)
    new(node.value)
  end

  def to_yaml(yaml : YAML::Nodes::Builder)
    yaml.scalar @value
  end

  def ==(other : self) : Bool
    @value == other.value
  end
end
```

Properties: callers access known values as `SizeUnit::TIB`, pass unknown values as
`SizeUnit.new("future-value")`, and the struct round-trips transparently through JSON/YAML.

Member constant naming follows the same all-caps rule used for regular `enum` members:
all-uppercase wire values (e.g. `"LINUX"`) are kept verbatim; mixed-case values are PascalCased.

### 3. Enum default literals

`crystal_literal` is extended to detect non-primitive `crystal_type` values (i.e., named types
from a `$ref`). For a string default on such a type, the generator emits `TypeName::MemberName`
using the same member-naming convention, matching what both closed enums and extensible-enum
structs define as constants. This ensures `default: "TiB"` on a `SizeUnit` property produces
`getter size_unit : SizeUnit = SizeUnit::TIB`.

## Consequences

**Good**

- Known values of extensible enums are named constants — `SizeUnit::TIB` instead of `"TiB"`.
- The struct accepts any `String`, so responses with future/unknown values deserialize without
  error.
- `default` values on enum and extensible-enum properties produce valid Crystal constant
  references, not bare string literals.
- Both JSON and YAML serialization are supported without including `JSON::Serializable` or
  `YAML::Serializable` (which would conflict with the custom `from_json`/`to_json` we emit).

**Bad / Trade-offs**

- Extensible-enum structs cannot be used in Crystal `case` expressions the way `enum` members
  can; callers must match on `.value` instead.
- The value struct is slightly more verbose to construct for unknown values (`SizeUnit.new("x")`)
  compared to a plain string.
- If a spec defines both `enum` and `x-extensible-enum` on the same schema, `enum` takes
  precedence (classified as `Enum`). Combining both fields on one schema is unsupported.
