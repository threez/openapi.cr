# ADR 013 — Client and Server Extension Hooks

## Status

Accepted

## Context

Generated client and server code is useful out of the box, but production systems
routinely need cross-cutting behaviour that the generator cannot anticipate:
distributed tracing, authentication, rate-limiting, structured logging, request
signing, retry logic, and metric emission. Without an explicit extension point,
users must fork the generated files or wrap every method manually — both of which
break on regeneration.

The two generated artefacts have different shapes, so the hooks are different:

- The **client** makes outgoing HTTP requests. The natural unit to intercept is the
  `HTTP::Request` object just before it is handed to the transport.
- The **server** receives incoming HTTP requests and dispatches them to an abstract
  handler method. The natural unit to intercept is the full dispatch block — param
  parsing, handler invocation, and response serialization — so that both pre- and
  post-processing are possible.

## Decision

### Client — `perform_request`

`OpenAPI::Client::Helpers` defines a concrete, overridable method:

```crystal
private def perform_request(operation : Symbol, request : HTTP::Request) : HTTP::Client::Response
  @http.exec(request)
end
```

Every generated operation method builds an `HTTP::Request` explicitly and calls
`perform_request` instead of calling `@http.get/post/…` directly. The default
delegates to the injected `HTTP::Client`.

Users subclass the generated client and override `perform_request`:

```crystal
class MyClient < Petstore::Client
  private def perform_request(operation : Symbol, request : HTTP::Request) : HTTP::Client::Response
    request.headers["Authorization"] = "Bearer #{@token}"
    start = Time.utc
    response = super
    Log.info { "#{operation} #{response.status_code} in #{Time.utc - start}" }
    response
  end
end
```

`super` forwards the (possibly mutated) request to `@http.exec`. The user may
re-implement the HTTP call entirely by omitting `super`.

### Server — `around_action`

`OpenAPI::Server::MuxHelpers` and `OpenAPI::Server::KemalHelpers` each define:

```crystal
def around_action(operation : Symbol, context, &block : -> Nil) : Nil
  yield
end
```

Every generated route block body is wrapped in a call to `around_action`:

```crystal
mux.get "/pets" do |ctx|
  around_action(:list_pets, ctx) do
    limit = query_int32(ctx, "limit")
    result = list_pets(limit)
    json_response ctx, 200, result
  end
rescue ex : Error
  json_error ctx, ex, 500
rescue ex : Exception
  …
end
```

The rescue clauses live outside the `around_action` call, so exceptions raised
inside the block (or inside the user's override) propagate outward and are still
caught by the generated error handling. Users who want to observe or suppress errors
inside the hook can add their own rescue:

```crystal
def around_action(operation : Symbol, context : Mux::Context, &block : -> Nil) : Nil
  tracer.in_span(operation.to_s, kind: :server) do |span|
    span.set_attribute("http.method", context.request.method)
    yield
    span.set_attribute("http.status_code", context.response.status_code)
  rescue ex
    span.record_exception(ex)
    span.status = :error
    raise  # re-raise so the outer rescue clauses write the HTTP error response
  end
end
```

`context` is untyped in the helper definition so the helpers compile without the
framework required. The concrete type (`Mux::Context` or `HTTP::Server::Context`)
is shown in the example emitted as a doc comment on the generated `Handler` class.

### Why `yield` and not a proc or return value

A block-with-yield is the idiomatic Crystal pattern for wrapping. It is the same
primitive used by `HTTP::Server::Handler`, `DB::Connection#transaction`, and every
Crystal web framework's middleware. Users already know the pattern; a proc or
callback object would be unfamiliar and would require explicit `.call`.

### Why the hooks are asymmetric

The client hook returns the response (`HTTP::Client::Response`) because the caller
must receive it. The server hook returns `Nil` because the response is written
in-place to `context.response` as a side effect; there is no value to thread
through. Symmetry for its own sake would introduce an unused return value on the
server side.

## Consequences

**Good**

- Distributed tracing, auth injection, logging, and retry logic are all achievable
  in user space with no generator changes and no regeneration risk.
- The extension points are documented directly in the generated files via doc
  comments, so users discover them without reading this ADR.
- The server's `around_action` wraps the full dispatch including param parsing, so
  a user can inspect or mutate the raw request before any framework processing
  occurs, and read the final status code after the response is written.
- Header-based trace propagation (W3C `traceparent`, B3) works naturally because
  `context.request.headers` is accessible before `yield`.

**Bad / Trade-offs**

- `around_action` wraps param parsing as well as the handler call. A user who only
  wants to intercept the handler invocation itself cannot do so without replicating
  the parsing logic. This is an acceptable trade-off: wrapping everything is the
  common case, and splitting the hook into parse / dispatch / respond phases would
  produce a more complex API for a rare use case.
- Errors raised inside `around_action` by the user's logic (e.g. auth failures)
  must be typed correctly to match the generated rescue clauses, or the user must
  add their own rescue inside the override. This is expected Crystal behaviour, not
  a limitation specific to this design.
- The `context` parameter in the helpers is untyped. IDEs and `crystal tool context`
  will not autocomplete its members without a type annotation. Users who want
  autocomplete should add the annotation in their override signature.
