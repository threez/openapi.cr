# ADR-004: Extensible Generator Architecture

**Status:** Accepted  
**Date:** 2026-06-20  
**Updated:** 2026-06-21

## Context

The Crystal HTTP ecosystem has several established frameworks with different routing
and middleware conventions (stdlib Mux, Kemal, Lucky, Grip). A server generator
hard-coded to one framework would exclude large portions of the Crystal community.
Beyond server adapters, new output categories may emerge over time — GraphQL schemas,
OpenTelemetry instrumentation, mock servers, etc.

The architecture must allow new generators to be added with minimal friction and no
changes to existing generators.

## Decision

All generators share a single abstract base class:

```crystal
abstract class OpenAPI::Generator::Base
  abstract def generate(doc : Model::Document, ctx : RenderContext) : Array(GeneratedFile)
end
```

Each generator is a self-contained class in its own file under
`src/openapi/generator/`. Adding a new generator requires:

1. Create `src/openapi/generator/<name>.cr` subclassing `Base`.
2. `require` it from `src/openapi/generator.cr`.
3. Add a `when "<name>"` branch in `Generator::Runner#generate`.

No changes to existing generators, no registry, no adapter hierarchy.

The four generators shipped today illustrate the pattern:

| Class | File | Output |
|---|---|---|
| `TypesGenerator` | `generator/types.cr` | Crystal classes/structs/enums for all schemas |
| `ClientGenerator` | `generator/client.cr` | Typed HTTP client, one method per operation |
| `ServerGenerator` | `generator/server.cr` | Abstract handler for the Mux router |
| `KemalServerGenerator` | `generator/kemal_server.cr` | Abstract handler for the Kemal framework |

`ServerGenerator` and `KemalServerGenerator` are independent classes rather than
a parameterised single class — each can evolve at its own pace and produce
idiomatic output for its target framework without sharing conditional logic.

### Runner

`Generator::Runner` is the single place that maps generator names to classes:

```crystal
runner = OpenAPI::Generator::Runner.new(doc, namespace: "Petstore",
  output_dir: "src/generated", formats: Set{"json"})

runner.run(%w[types client server kemal])
```

`Runner#generate(name)` raises `ArgumentError` on an unknown name, giving a clear
error message that lists valid options.

## Consequences

- **Positive**: Adding a new generator is a three-step change confined to one new
  file plus two lines in existing files.
- **Positive**: Each generator is independently testable and can be used
  programmatically without the CLI.
- **Positive**: Framework-specific generators produce idiomatic output with no
  shared conditional logic.
- **Negative**: `Runner` needs a new `when` branch for each new generator — it is
  a small but intentional registry that must be kept in sync.
