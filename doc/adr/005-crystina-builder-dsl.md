# ADR-005: Crystina Builder DSL Instead of a Template Engine

**Status:** Accepted  
**Date:** 2026-06-20  
**Updated:** 2026-06-21

## Context

Code generation requires a strategy for turning model data into source text.
The options considered were:

| Approach | Pros | Cons |
|---|---|---|
| Template engine (Crinja/ECR) | Familiar Jinja2 syntax, separation of structure from logic | Errors surface at runtime; external dependency; contributors need two languages |
| Direct IO building in Crystal | Compile-time type-checking; no dependency; single language | Logic and structure are deeply interleaved; indent tracking is manual and error-prone |
| Builder DSL (Crystina) | Compile-time type-checking; indent-free emit methods; structured nodes | External shard dependency |

The initial design called for Crinja (a Jinja2-compatible engine). The deciding
factor against it was that **template errors surface at runtime** — a broken
template only fails when the generator is invoked, not when the generator is
compiled. For a tool whose entire output is source code, correctness guarantees
matter more than template syntax familiarity.

Direct IO generation was the first working implementation, but indent tracking
proved fragile: every `emit_*` method had to accept and thread an `indent :
String` parameter, and word-wrapping logic required threading an `available :
Int32` parameter separately. Adding a nesting level meant updating every method
in the call chain.

## Decision

Generators build output using **Crystina** ([`threez/crystina.cr`](https://github.com/threez/crystina.cr)),
a published shard that represents Crystal source code as a tree of typed nodes
(`Comment`, `Line`, `Block`, `Sequence`, etc.) and renders them with correct indentation.

```crystal
b.scope("module #{namespace}") { |inner|
  inner.scope("class #{class_name}") { |kb|
    properties.each { |p| emit_property(p, kb) }
  }
}
```

Each generator composes a `Crystina::Builder`, passes it into small private
`emit_*` methods, and calls `b.to_s` at the end. `emit_*` methods accept only
domain data and a `Builder` — no indent string, no available-width counter.
Indentation is a rendering concern handled by the node tree.

Comment word-wrapping is a property of the `Comment` node itself (`wrap: :auto`
detects single-line text and wraps to fit the render-time column width), so
callers never compute available column width.

### Trade-offs accepted

- **External shard dependency** — a Crystina release that changes its API could
  require updates here. Pinning via `shard.lock` mitigates this in practice.
- **`scope` instead of typed helpers for some constructs** — `struct`, `class`,
  and `module` blocks use `b.scope("struct Foo")` rather than a dedicated
  `b.struct_def` with block because Crystal's `with child yield` prevents
  explicit block parameters. This is a minor readability trade-off.

## Consequences

- **Positive**: All generation logic is type-checked at compile time — a broken
  generator is a compile error, not a runtime failure.
- **Positive**: `emit_*` methods accept only a `Builder`; indent level and
  column width are derived automatically at render time from the node tree.
- **Positive**: No template engine dependency; Crystina is a lightweight,
  purpose-built shard with no transitive dependencies of its own.
- **Positive**: Contributors read and write only Crystal — no Jinja2 syntax to
  learn, no context-switching between languages.
- **Positive**: Generator logic can use the full Crystal standard library
  directly (sorting, filtering, string manipulation) without custom filter
  registration.
- **Negative**: Output formatting correctness depends on `Crystina` node
  implementations — a bug in `Block#render` affects every generated construct
  that uses blocks, offset by Crystina's own spec suite in its repo.
