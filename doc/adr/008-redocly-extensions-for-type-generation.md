# ADR 008 — Support Redocly OpenAPI Extensions for Better Type Generation

## Status

Accepted

## Context

OpenAPI 3.x allows vendors to annotate specifications with `x-*` extension fields.
Redocly's portal toolchain defines a well-documented set of extensions that carry
semantics beyond the base spec — most importantly, two extensions that directly
improve the quality of generated Crystal types:

- **`x-enumDescriptions`** — a `Hash(String, String)` mapping each enum value to
  a Markdown description. Without this extension the generator emits member names
  only; with it, per-member documentation appears in generated code.

- **`x-additionalPropertiesName`** — a human-readable name for the dynamic keys of
  an `additionalProperties` map. The base spec says only that a schema's extra
  properties are keyed by `String`; this extension names what those strings
  represent (e.g. `"labelName"`, `"regionCode"`), enabling the generator to
  produce a more meaningful type alias and a documentation comment.

Real-world API specs (Stripe, IONOS, Redocly-documented public APIs) use these
extensions heavily. Ignoring them degrades the generated code: enums lose their
inline documentation, and map types silently lose their semantic key names.

Other Redocly extensions (`x-tagGroups`, `x-codeSamples`, `x-rbac`, etc.) affect
portal rendering or access control, not type structure, so they are parsed and
stored on the model but not acted on during type generation.

## Decision

1. **Model layer**: parse all Redocly extensions into typed model fields (done in
   `src/openapi/model/extensions.cr` and the six affected model files).

2. **Type generator — `x-enumDescriptions`**: when a schema has `x-enumDescriptions`,
   emit the corresponding description as a `#` comment immediately above each enum
   member. The comment is word-wrapped to 80 characters using the same logic as
   type-level descriptions.

3. **Type generator — `x-additionalPropertiesName`**:
   - `TypeMapper.crystal_type` returns `Hash(String, ValueType)` for any schema
     whose only structural element is `additionalProperties` with a typed schema
     (previously such schemas fell through to `JSON::Any`).
   - When `x-additionalPropertiesName` is present on the `additionalProperties`
     sub-schema, a `# Keys: <name>` comment is emitted above the alias or getter.

4. All other Redocly extensions are available on the model for use by custom hooks
   or future generators (client, server), but are not acted on in the default
   types generator.

## Consequences

**Good**

- Generated enums include the same documentation the API author wrote, making the
  Crystal types self-explanatory without needing to cross-reference the spec.
- `Hash(String, ValueType)` is a precise, usable Crystal type; `JSON::Any` is not.
  Callers that previously needed to cast can now use the hash directly.
- The hook system lets authors override or suppress these behaviours per-schema.

**Bad / Trade-offs**

- The generator now has a dependency on extension semantics from a specific vendor
  (Redocly). Specs that use different naming conventions for the same ideas (e.g.
  `x-enum-descriptions` from other toolchains) will not be handled automatically;
  they require a custom `Hooks` subclass.
- `additionalProperties` schemas with both fixed `properties` and a wildcard map
  are treated as regular classes; the map part is not reflected in the type. Full
  support for mixed schemas is deferred.
