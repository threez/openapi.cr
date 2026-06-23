# ADR-002: Rich Typed OpenAPI v3 Model

**Status:** Accepted  
**Date:** 2026-06-20

## Context

The generator needs an internal representation of an OpenAPI 3.x document. Options:

1. **Loose map** — parse the document into `Hash(String, YAML::Any)` and access
   fields by string key at generation time.
2. **Rich typed model** — a Crystal struct/class hierarchy mirroring every object
   type in the OpenAPI 3.x specification.
3. **Minimal typed model** — only the fields the generators actually use.

`getkin/kin-openapi` (the reference Go implementation) took the rich typed approach
and it paid off: generators, validators, and middleware all operate on a stable,
typed API, and the model itself serves as machine-readable documentation of the spec.

## Decision

Implement a **rich typed Crystal model** covering the full OpenAPI 3.x object
hierarchy, living in `src/openapi/model/`.

### Core types

| Crystal type | OpenAPI object |
|---|---|
| `OpenAPI::Model::Document` | Root OpenAPI document |
| `OpenAPI::Model::Info` | Info object |
| `OpenAPI::Model::Server` | Server object |
| `OpenAPI::Model::PathItem` | Path Item object |
| `OpenAPI::Model::Operation` | Operation object |
| `OpenAPI::Model::Parameter` | Parameter object |
| `OpenAPI::Model::RequestBody` | Request Body object |
| `OpenAPI::Model::Response` | Response object |
| `OpenAPI::Model::Schema` | Schema object (JSON Schema subset) |
| `OpenAPI::Model::SchemaRef` | `$ref` or inline Schema (see below) |
| `OpenAPI::Model::Components` | Components object |
| `OpenAPI::Model::SecurityScheme` | Security Scheme object |
| `OpenAPI::Model::Tag` | Tag object |
| `OpenAPI::Model::MediaType` | Media Type object |
| `OpenAPI::Model::Header` | Header object |
| `OpenAPI::Model::Link` | Link object |
| `OpenAPI::Model::Callback` | Callback object |
| `OpenAPI::Model::Example` | Example object |

### SchemaRef pattern

Any field in the spec that may be either an inline object or a `$ref` string uses
the `SchemaRef(T)` union type:

```crystal
# Unresolved after parse; Resolved after the resolver pass (see ADR-007)
alias SchemaRef(T) = Ref(T) | T

struct Ref(T)
  getter ref : String   # raw "$ref" value, e.g. "#/components/schemas/Pet"
  property resolved : T?
end
```

This mirrors kin-openapi's `SchemaRef` / `Ref[T]` design.

### Serialisation

Parse via `YAML::Serializable` (YAML source) and `JSON::Serializable` (JSON source).
Extension fields (`x-*`) are captured as `Hash(String, JSON::Any)` on each object.

## Consequences

- **Positive**: Generators, validators, and future tooling operate on a stable,
  typed Crystal API — no stringly-typed field access.
- **Positive**: The model is self-documenting; it mirrors the OpenAPI specification
  object-for-object.
- **Positive**: Compile-time exhaustiveness checks when switching on discriminated
  unions (e.g., schema composition).
- **Negative**: Large surface area to maintain; upstream spec changes require model
  updates.
- **Negative**: Initial implementation effort is significant (50+ types).
- **Mitigation**: Start with the subset needed by the first generator target and
  expand incrementally; use `TODO` stubs for rarely-used objects.
