# ADR-001: Crystal as Implementation Language

**Status:** Accepted  
**Date:** 2026-06-20

## Context

We need a host language for the OpenAPI code generator. The generator must produce
fast, reliable output; ship as a single self-contained binary; and handle large
OpenAPI specs without performance issues. The author has existing familiarity with
Ruby-like syntax and values strong static typing for a tool with a complex internal
model.

Candidates considered:

| Language | Pros | Cons |
|----------|------|------|
| Crystal  | Compiled, typed, Ruby ergonomics, macro system, single binary | Smaller ecosystem, 1.x maturity |
| Go       | Large ecosystem, excellent tooling (kin-openapi exists) | Verbose, no macros for compile-time embedding |
| Ruby     | Familiar, fast iteration | Not compiled, slow startup, no static types |
| Rust     | Maximum performance, type safety | High learning curve, slower iteration |

## Decision

Use **Crystal ≥ 1.20.2** as the sole implementation language.

Key reasons:
- **Compiled binary**: Users install one artifact; no runtime dependency.
- **Static typing with inference**: The OpenAPI model requires hundreds of distinct
  types; Crystal's type system catches model mismatches at compile time.
- **Macro system**: Crystal macros enable compile-time template embedding
  (`{{ read_file "..." }}`), making embedded-template ADR-006 straightforward.
- **YAML/JSON built-ins**: `YAML::Serializable` and `JSON::Serializable` are
  first-class, covering the two OpenAPI source formats without extra dependencies.
- **Ergonomics**: Ruby-like syntax reduces boilerplate for the large model layer.

## Consequences

- **Positive**: Single binary distribution; compile-time safety across the entire
  model; fast generation even for large specs.
- **Positive**: Crystal's `shards` package manager is simple and reproducible.
- **Negative**: The Crystal shard ecosystem is smaller than Go or Rust; some
  libraries may need to be written from scratch.
- **Negative**: Crystal is not yet 2.0; some APIs may change. Pinning `>= 1.20.2`
  mitigates this.
- **Accepted risk**: Multi-threading is possible via `spawn`/channels but the
  generator will be single-threaded in v0.1 for simplicity.
