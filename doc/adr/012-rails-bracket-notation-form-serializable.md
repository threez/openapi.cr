# ADR 012 — Rails Bracket Notation in Form::Serializable

## Status

Accepted

## Context

Stripe's REST API is a Rails application. All write operations use
`application/x-www-form-urlencoded` with deeply nested structures encoded in
Rails/Rack bracket notation:

```
address[city]=SF&address[zip]=94105
expand[]=data&expand[]=metadata
line_items[0][name]=T-shirt&line_items[0][amount]=1500
payment_method_types[]=card
```

The original `OpenAPI::Form::Serializable` encoded only flat scalar fields.
Nested `Form::Serializable` objects and arrays were silently dropped. Generating
a Stripe client produced request bodies with only the top-level scalar fields,
making every complex call silently broken.

`application/x-www-form-urlencoded` has no standard for encoding nested
structures. Rails/Rack bracket notation (`address[city]=SF`, `tags[]=a`) is the
most widely implemented convention: Rack, PHP's `http_build_query`, jQuery,
axios, and curl's `-d` flag all parse or produce it. Choosing the most broadly
recognised encoding makes the default serializer correct for the largest class of
real-world form-based APIs without any additional configuration. An API that uses
a different convention can provide a custom serializer (see Consequences).

## Decision

### 1. Encoding rules

The module now encodes every supported Crystal type using Rack's bracket notation:

| Field type | Wire format |
|---|---|
| Scalar (`String`, `Int*`, `Float*`, `Bool`) | `name=value` |
| Nested `Form::Serializable` | `address[city]=SF&address[zip]=94105` |
| Array of scalars | `tags[]=ruby&tags[]=rails` |
| Array of `Form::Serializable` | `items[0][name]=X&items[1][name]=Y` |
| Array of `openapi_enum` | `payment_method_types[]=card` (via `wire_value`) |

Explicit numeric indices are used for arrays of objects (`[0]`, `[1]`, …). Rack
accepts both `[]` and `[n]` forms equivalently, so this is compatible with
`line_items[][name]` style requests.

### 2. `_form_append(p, prefix)` recursive workhorse

`to_form_params` becomes a thin wrapper:

```crystal
def to_form_params : String
  HTTP::Params.build { |_p| _form_append(_p, nil) }
end
```

`_form_append(p, prefix)` carries the accumulated bracket prefix down through
recursive calls. The module-level helper:

```crystal
def self.build_key(prefix : String?, field : String) : String
  prefix ? "#{prefix}[#{field}]" : field
end
```

produces `field` at the top level and `prefix[field]` for nested calls, without
duplicating the `nil`-check across every branch of the macro loop.

For nested `Form::Serializable` objects the call is:

```crystal
val._form_append(p, OpenAPI::Form::Serializable.build_key(prefix, key))
```

For indexed arrays of `Form::Serializable`:

```crystal
arr.each_with_index { |e, i| e._form_append(p, "#{k}[#{i}]") }
```

### 3. `{% verbatim do %}` requirement

The macro loop `{% for ivar in @type.instance_vars %}` inside an instance method
defined within `macro included` normally expands at include time. At that point
the including type's instance variables are not yet declared, causing a
compilation error ("instance vars not yet initialized").

Wrapping the method body in `{% verbatim do %}{% begin %}...{% end %}{% end %}`
defers all macro expansion inside that scope to method-compilation time, when the
type is fully resolved and its instance vars are available. This is required for
any instance method inside `macro included` whose body contains a top-level
`{% for ivar in @type.instance_vars %}` loop (as opposed to a loop inside a block
passed to a method, which is deferred by the block boundary).

### 4. Enum array detection at macro time

Crystal's macro `TypeNode` does not expose `instance_methods`. To detect
`openapi_enum`-generated arrays, the macro checks:

```crystal
{% elsif elem_t <= Enum %}
  arr.each { |e| p.add(key + "[]", e.wire_value) }
```

All `openapi_enum` types are Crystal `enum`s and always define `wire_value`.
Non-openapi enums used in form params must also define `wire_value` or they
produce a clear compile error — an appropriate constraint given that form
encoding requires a controlled wire representation.

### 5. `from_form_params` prefix threading

The deserializer signature becomes:

```crystal
def self.from_form_params(params : HTTP::Params, prefix : String? = nil) : self
```

All key lookups use `build_key(prefix, key)`. For nilable nested `Form::Serializable`
fields, a key-scan determines presence before attempting deserialization:

```crystal
_present = false
params.each { |_k, _| _present = true if _k.starts_with?(_nk + "[") }
_present ? NestedType.from_form_params(params, _nk) : nil
```

This prevents `KeyError` when the nested object is absent, without requiring a
sentinel key or a default value.

Deserialization of indexed arrays (`items[0][field]`, `items[1][field]`) is
intentionally out of scope. Generated REST clients construct Crystal objects
directly and submit them via `to_form_params`; round-tripping indexed arrays
from raw params is a server-side concern not required here.

## Consequences

**Good**

- Generated Stripe clients (and any other Rails-based API clients) produce
  correct request bodies for nested objects, scalar arrays, and enum arrays.
- The recursive `_form_append` pattern scales to arbitrary nesting depth without
  generator changes.
- `from_form_params` with prefix threading enables round-trip testing of nested
  types in specs.

**Bad / Trade-offs**

- The `{% verbatim do %}` wrapping pattern is non-obvious and must be applied to
  any future instance method added inside `macro included` that iterates
  `@type.instance_vars` at the top level. This is a Crystal macro constraint,
  not a design choice, but it requires awareness from contributors.
- Deserialization of indexed arrays (`items[0][name]`, `items[1][name]`) is
  deferred. A form body submitted by an external system using indexed arrays
  cannot be fully round-tripped with the current `from_form_params`.
- `elem_t <= Enum` for enum detection means any Crystal enum in a form array
  must define `wire_value`. Standard Crystal enums (not produced by `openapi_enum`)
  will fail to compile if placed in a form-encoded array field without adding
  `wire_value` themselves.
- Rails bracket notation is the most widely recognised convention for nested form
  data, but it is not universal. APIs that use dot-notation, PHP nested arrays
  without explicit brackets, or a proprietary scheme will produce incorrect request
  bodies with the default serializer. The generator CLI should accept a
  `--form-serializer` option (a fully-qualified Crystal module name) that is
  emitted in place of `OpenAPI::Form::Serializable` in the `include` line of
  generated request-body types. The custom module must expose the same
  `to_form_params : String` and
  `self.from_form_params(params : HTTP::Params, prefix : String? = nil) : self`
  interface. This extensibility point is not yet implemented; it is deferred to a
  future generator CLI iteration.
