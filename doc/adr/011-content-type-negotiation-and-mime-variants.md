# ADR 011 — Content-Type Negotiation and MIME Variant Support

## Status

Accepted

## Context

OpenAPI operations declare their request and response body formats via the
`content` map, whose keys are MIME type strings. The generator previously matched
only `"application/json"` and `"application/yaml"` exactly. Two problems followed:

1. **Silent fall-through for variants.** MIME types such as `text/json`,
   `text/yaml`, `application/x-yaml`, and `text/x-yaml` appear in real-world
   specs (Stripe uses `application/x-www-form-urlencoded`; some APIs publish
   `text/yaml` schemas). Exact-match code generation treated them as unrecognised
   and fell through to `:raw` or `:multi`, producing incorrect serialization calls.

2. **Overly broad `:multi` mode.** A single `:multi` symbol was used whenever an
   operation was not pure JSON. This blurred the distinction between operations
   that genuinely accept several content types at runtime and those that only
   accept YAML or only accept form data. Generated clients emitted the heavier
   `serialize_body` / `parse_typed_response` helpers for cases where a cheaper
   format-specific helper would suffice — and for JSON-only types that lack YAML
   serialization, caused compilation failures.

3. **Conditional helper inclusion.** Generated clients only `include
   OpenAPI::Client::Helpers` when the operation was classified as `:multi`. For
   other operations the helpers were absent, making the generated API inconsistent
   and preventing callers from reusing helper methods.

## Decision

### 1. MIME variant constants

Two constants are defined at module level in `OpenAPI::Generator::ParamValidation`
and reused by `Collector` and `Types`:

```crystal
JSON_CONTENT_TYPES = ["application/json", "text/json"]
YAML_CONTENT_TYPES = ["application/yaml", "text/yaml", "application/x-yaml", "text/x-yaml"]
```

All content-key lookups use `any? { |k, _| CONSTANTS.includes?(k) }` instead of
exact hash lookups. This closes the variant gap without special-casing individual
MIME strings across multiple files.

### 2. Fine-grained `content_mode` classification

`content_mode` returns one of six symbols:

| Symbol | Meaning |
|---|---|
| `:none` | No request body |
| `:json_only` | Only JSON variants present |
| `:yaml_only` | Only YAML variants present |
| `:form_only` | Only `application/x-www-form-urlencoded` present |
| `:multi` | Two or more format families present |
| `:raw` | Some other single content type |

The generator selects the serialization / deserialization helper based on this
symbol. `:multi` is now reserved for operations that genuinely accept multiple
format families and require runtime negotiation.

### 3. Format-specific client helpers

`OpenAPI::Client::Helpers` ships three serializers and two deserializers:

```crystal
private def serialize_json_body(body) : {String, String}
private def serialize_yaml_body(body) : {String, String}
private def serialize_form_body(body) : {String, String}

private def parse_json_response(response, type : T.class) : T forall T
private def parse_yaml_response(response, type : T.class) : T forall T
```

Each helper constrains T to only the required capability (`from_json` or
`from_yaml`). The pre-existing `serialize_body` and `parse_typed_response` are
retained exclusively for `:multi` operations that need runtime content-type
negotiation.

### 4. Why format-specific helpers are required

Crystal generics are compiled monomorphically: every concrete T instantiated
with a generic method must satisfy all constraints visible in the method body.
A single `parse_typed_response` that calls both `T.from_json` and `T.from_yaml`
forces every response type to implement YAML deserialization, even for JSON-only
APIs. JSON-only generated types (e.g. Petstore's `Pet`) do not include
`YAML::Serializable`, so the single generic caused compile errors. Splitting into
format-specific helpers removes the spurious constraint.

### 5. Always include client helpers

Generated clients now unconditionally emit `include OpenAPI::Client::Helpers`
regardless of content mode. The helpers are pure private methods with no side
effects; including them for all clients costs nothing and ensures a consistent
interface.

## Consequences

**Good**

- MIME variants (`text/json`, `text/yaml`, `application/x-yaml`, `text/x-yaml`)
  are handled correctly in code generation without special-casing.
- JSON-only generated types compile without requiring YAML serialization.
- Generated clients have a uniform interface regardless of their content modes.
- The `:multi` path is narrower and only fires when genuinely needed, reducing
  unnecessary runtime branching in the common case.

**Bad / Trade-offs**

- `JSON_CONTENT_TYPES` and `YAML_CONTENT_TYPES` are defined in `ParamValidation`
  and referenced from `Collector` and `Types` — a mild coupling across generator
  subsystems. A shared `ContentTypes` module would be cleaner but is deferred
  until a third consumer emerges.
- Runtime helpers (`serialize_body`, `parse_typed_response`) still use substring
  matching (`includes?("yaml")`) rather than the constant arrays. This is
  acceptable because runtime content-type strings are not controlled by the
  generator; the mismatch is noted for future alignment.
