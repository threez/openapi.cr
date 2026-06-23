# ADR-007: $ref Resolution Strategy

**Status:** Accepted  
**Date:** 2026-06-20

## Context

OpenAPI 3.x uses JSON Reference (`$ref`) extensively to avoid repetition:

```yaml
components:
  schemas:
    Pet:
      type: object
      properties:
        id: { type: integer }

paths:
  /pets:
    get:
      responses:
        "200":
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Pet'
```

A generator that operates on unresolved `$ref` strings cannot introspect the
referenced type's structure. Resolution must happen before generation.

`$ref` can point to:
1. **Intra-document** — `#/components/schemas/Pet` (JSON Pointer within the same file).
2. **External file** — `./other.yaml#/components/schemas/Address`.
3. **Remote URL** — `https://example.com/schemas/common.yaml#/Foo`.
4. **Circular** — `#/components/schemas/Node` references itself (linked lists, trees).

## Decision

Implement **two-pass loading** with intra-document resolution in v0.1.

### Pass 1 — Parse

Deserialise the YAML/JSON document into the typed model (ADR-002). Any field that
can be a `$ref` is represented as `SchemaRef(T)`. After parsing, all refs are
`SchemaRef::Unresolved(ref_string)`.

### Pass 2 — Resolve (`src/openapi/resolver.cr`)

Walk the parsed document tree. For each `SchemaRef::Unresolved(ref)`:

1. **Parse the ref string** using a simple pattern match:
   - `#/components/...` → intra-document
   - anything else → unsupported in v0.1
2. **Navigate the `components` registry** using the JSON Pointer path segments.
3. **Replace** `Unresolved` with `Resolved(T)` in-place.
4. **Circular ref guard**: maintain a `Set(String)` of refs currently being resolved.
   If a ref is encountered that is already in the set, raise `CircularReferenceError`
   with a breadcrumb trail.

```crystal
class OpenAPI::Resolver
  def resolve(doc : Model::Document) : Model::Document
    @visiting = Set(String).new
    resolve_document(doc)
    doc
  end
end
```

### v0.1 scope

| Ref type | v0.1 |
|---|---|
| Intra-document `#/components/...` | Supported |
| External file `./other.yaml` | Raises `NotSupportedError` with clear message |
| Remote URL `https://...` | Raises `NotSupportedError` with clear message |
| Circular refs | Detected; raises `CircularReferenceError` |

### Future

External file refs will be added in v0.2 via a `FileLoader` interface. Remote URL
refs may be added later with an opt-in `--allow-remote-refs` flag.

## Consequences

- **Positive**: Generators operate on a fully resolved model — no ref-chasing at
  generation time.
- **Positive**: Circular reference detection prevents infinite loops.
- **Positive**: Clear error messages for unsupported ref types guide users.
- **Negative**: Intra-document-only resolution blocks specs that use multi-file
  `$ref` composition. This is a known v0.1 limitation.
- **Mitigation**: Many real-world specs (especially those exported from API design
  tools) are single-file and work within v0.1 scope.
