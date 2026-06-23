# ADR-003: Generator Architecture

**Status:** Accepted  
**Date:** 2026-06-20  
**Updated:** 2026-06-21

## Context

An OpenAPI generator can produce several categories of output from the same spec:

- **Types / models** — data structures representing request/response bodies.
- **Client** — HTTP call wrappers that consume an API.
- **Server** — route skeletons and handler stubs that implement an API.
- **Framework-specific server** — adapter variants for frameworks like Kemal.

These outputs have different consumers (library users vs. API implementors), different
structures, and different dependencies on the model. Mixing them into a single generator
creates coupling and makes selective generation impossible.

## Decision

Split generation into **independent generator classes**, each in its own file:

```
src/openapi/generator/
  types.cr         # TypesGenerator  — schemas → Crystal classes/structs/enums
  client.cr        # ClientGenerator — operations → typed HTTP client methods
  server.cr        # ServerGenerator — operations → abstract Mux handler
  kemal_server.cr  # KemalServerGenerator — operations → abstract Kemal handler
  runner.cr        # Runner — orchestrates any combination of the above
```

Each generator follows the same interface:

```crystal
abstract class OpenAPI::Generator::Base
  abstract def generate(doc : Model::Document, ctx : RenderContext) : Array(GeneratedFile)
end
```

Generators build output by writing directly to an `IO::Memory` buffer — no template
engine is involved. This keeps the dependency footprint minimal and makes the output
fully type-checked at compile time.

`RenderContext` carries the options that are common to all generators:

```crystal
class OpenAPI::Generator::RenderContext
  getter namespace : String    # Crystal module to wrap output in
  getter output_path : String  # destination file path (used in the GeneratedFile record)
  getter formats : Set(String) # serialization formats to emit, e.g. Set{"json", "yaml"}
end
```

### Runner

`Generator::Runner` orchestrates one or more generators against a single document,
handling output-path construction and `RenderContext` creation so callers do not need
to wire these up themselves:

```crystal
runner = OpenAPI::Generator::Runner.new(
  doc,
  namespace:  "Petstore",
  output_dir: "src/generated",
  formats:    Set{"json"},
  hooks:      my_hooks,
)

runner.run(%w[types client server])   # returns Array({String, String}) — path + content
runner.generate("kemal")              # single generator, raises ArgumentError if unknown
```

### CLI surface

The `cryogen` binary exposes all options as flags on a single command:

```
cryogen [options] <spec-file>

  --namespace NAME      Crystal module namespace (default: derived from filename)
  --output DIR          Output directory (default: .)
  --generators LIST     types,client,server,kemal (default: types,client,server)
  --formats LIST        json,yaml (default: json,yaml)
  --custom-scalar MAP   Override a scalar type, e.g. string:ipv4=IPv4 (repeatable)
```

### Shared utilities

Cross-cutting helpers live under `src/openapi/generator/types/` and are used by all
generators:

- `NameInflector` — snake_case, PascalCase, safe identifier transformations
- `TypeMapper` — OpenAPI type+format → Crystal type (with a built-in `SCALAR_MAP`)
- `Hooks` — extension points for custom type mappings, name overrides, and schema skipping
- `Collector` — walks the document and produces a flat list of `ClassifiedSchema` records
- `Emitter` — renders a single `ClassifiedSchema` to Crystal source

## Consequences

- **Positive**: Users can generate only what they need; types-only is common in
  shared library scenarios.
- **Positive**: Each generator can be tested and evolved independently.
- **Positive**: `Runner` provides a clean programmatic API for tooling that embeds
  the generator without going through the CLI.
- **Positive**: No template engine dependency — output is built directly in Crystal,
  so it is type-checked and there is no template language to learn or maintain.
- **Positive**: `Hooks` allow custom scalar mappings and name overrides without
  forking or subclassing the generators.
- **Negative**: Adding a new output variant (e.g. a new server adapter) requires a
  new generator class and a new case branch in `Runner` rather than a new template file.
