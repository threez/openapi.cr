# ADR 010 — Runtime Validation for Generated Types

## Status

Accepted

## Context

OpenAPI's JSON Schema subset defines value constraints — `minimum`, `maximum`,
`minLength`, `maxLength`, `pattern`, `minItems`, `maxItems`, and inline `enum`
— via fields on the `Schema` object. The generator has always parsed these fields
(they live on `Model::Schema`) but discarded them during code emission. Generated
Crystal types carry no enforcement of the constraints the spec author declared.

The consequence: invalid values pass through deserialization and reach application
logic unchecked. A `gid` field documented as `0..65534` can hold `99999` without
any complaint from the generated type.

Real-world fixtures demonstrate the gap:

- **IONOS NFS v1** — `minimum: 0`, `maximum: 65534` on `uid`/`gid` fields
- **IONOS NFS v1** — `minimum: 1`, `maximum: 1000` on pagination parameters
- **Stripe** — extensive `maxLength` constraints (5000, 40000, 500, etc.)

## Decision

### 1. Runtime library — `src/openapi/validation/error.cr`

Two types shipped as part of the `openapi` shard:

- `OpenAPI::Validation::Error` — a struct holding `field`, `value`, `message`,
  `constraint`, and `constraint_value` (all `String`). Stringified value keeps the
  type simple and dependency-free.
- `OpenAPI::Validation::Exception < ::Exception` — wraps `Array(Error)`;
  `message` joins all error messages with `"; "`.

Shipping in the shard (rather than code-generating the types inline) avoids
duplicating the `Error` definition across every generated file when a project
generates multiple type files.

### 2. Runtime library — `src/openapi/validation/helpers.cr`

A module `OpenAPI::Validation::Helpers` ships with the shard alongside `Error`.
It provides eight private helper methods — `validate_min_length`,
`validate_max_length`, `validate_pattern`, `validate_minimum`, `validate_maximum`,
`validate_min_items`, `validate_max_items`, and `validate_enum` — each with the
signature:

```crystal
validate_max_length(errors : Array(Error), field : String, value : String?, max : Int) : Nil
```

Each helper appends to the `errors` array when the constraint is violated and
returns immediately when the value is `nil` (optional-field skip). `forall T`
generics handle numeric and array helpers without boxing or per-type overloads.

### 3. Generated `valid?` and `validate!`

For every `class` or `struct` kind where at least one property carries a constraint,
the emitter includes the helpers and appends two methods after the properties block:

```crystal
include OpenAPI::Validation::Helpers

def valid? : Array(OpenAPI::Validation::Error)
  errors = [] of OpenAPI::Validation::Error
  validate_max_length errors, "api_version", @api_version, 5000
  validate_minimum errors, "gid", @gid, 0
  validate_pattern errors, "name", @name, /^[a-z]+$/, "^[a-z]+$"
  errors
end

def validate! : Nil
  errors = valid?
  raise OpenAPI::Validation::Exception.new(errors) unless errors.empty?
end
```

Each constrained property becomes one line per constraint; nil handling is fully
inside the helper, so the generator emits no nullable-wrapping boilerplate.

`validate!` always calls `valid?` and raises a single exception wrapping all
violations — callers see the complete picture, not just the first failure.

### 4. Constraint coverage (first iteration)

`minimum`, `maximum`, `minLength`, `maxLength`, `pattern`, `minItems`, `maxItems`,
and inline `enum` on untyped string properties. Deferred: `exclusiveMinimum`,
`exclusiveMaximum`, `multipleOf`, `uniqueItems`, `minProperties`, `maxProperties`.

### 5. Generated file header

Both `require "openapi/validation/error"` and `require "openapi/validation/helpers"`
are added to the header only when the file contains at least one type with
validation methods — keeping unconstrained output files unchanged.

## Consequences

**Good**

- Generated types with constraints are now validatable at runtime without any
  manual boilerplate.
- The `valid?` / `validate!` interface is idiomatic Crystal: callers can collect
  all errors or raise immediately.
- Generated types with no constraints are completely unaffected — zero output diff.
- The runtime types (`Error`, `Exception`) are small, dependency-free, and stable.

**Bad / Trade-offs**

- The `openapi` shard becomes a runtime dependency (not dev-only) for projects
  that use generated `valid?`/`validate!` methods.
- Constraint logic is duplicated between the emitter (`has_constraints?`) and the
  generator header helper (`needs_validation?`) — they cannot share a private
  method across class boundaries. A future refactor could extract a shared
  `Constraints` module if more callers emerge.
- Named enum schemas (classified as `SchemaKind::Enum` → Crystal `enum`) already
  enforce valid values at deserialization; this ADR does not add redundant checks
  for them. Only inline `enum` on untyped string properties gets a runtime check.
- `validate_pattern` receives the regex both as a `Regex` literal (for matching)
  and as a `String` (for the error message), since Crystal regex literals cannot
  be round-tripped back to their source string at runtime.
