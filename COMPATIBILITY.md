# OpenAPI 3.0.3 Compatibility Summary

High-level compliance tables for the Crystal `openapi` generator against OAS 3.0.3.

Legend: ✅ Compliant · ⚠️ Partial · ❌ Not implemented · ➖ Intentionally delegated

---

## Model Parsing (all spec objects)

| Spec Object | Parse Status | Gaps |
|---|:---:|---|
| OpenAPI Object | ✅ | — |
| Info Object | ✅ | — |
| Contact Object | ✅ | — |
| License Object | ✅ | — |
| Server Object | ✅ | — |
| Server Variable Object | ✅ | — |
| Paths Object | ✅ | — |
| Path Item Object | ✅ | Internal `$ref` resolved; external file refs explicitly not supported (security) |
| Operation Object | ✅ | — |
| External Documentation Object | ✅ | — |
| Parameter Object | ✅ | All fields parsed |
| Request Body Object | ✅ | — |
| Media Type Object | ✅ | — |
| Encoding Object | ✅ | Parsed; never used |
| Responses Object | ✅ | — |
| Response Object | ✅ | — |
| Callback Object | ✅ | Parsed; never used |
| Example Object | ✅ | — |
| Link Object | ✅ | Parsed; never used |
| Header Object | ✅ | Parsed; never used in generation |
| Tag Object | ✅ | — |
| Reference Object (`$ref`) | ⚠️ | Internal refs resolved; external file refs explicitly not supported (security — no arbitrary file/network access) |
| Schema Object | ✅ | All spec fields present |
| Discriminator Object | ✅ | — |
| XML Object | ✅ | `namespace`/`prefix` parsed but not applied |
| Security Scheme Object | ✅ | — |
| OAuth Flows Object | ✅ | — |
| OAuth Flow Object | ✅ | — |
| Security Requirement Object | ✅ | Parsed; not used in generation |

---

## Schema Object Field Coverage

| Field Category | Fields | Status | Notes |
|---|---|:---:|---|
| Core keywords | `type`, `format`, `title`, `description`, `default`, `example` | ✅ | All parsed and used |
| Numeric constraints | `minimum`, `maximum`, `multipleOf` | ✅ | All validated in generated code |
| Exclusive bounds | `exclusiveMinimum`, `exclusiveMaximum` | ✅ | Exclusive flag applied in generated validators |
| String constraints | `minLength`, `maxLength`, `pattern` | ✅ | All validated in generated code |
| Array constraints | `items`, `minItems`, `maxItems`, `uniqueItems` | ✅ | All validated in generated code |
| Object constraints | `properties`, `required`, `additionalProperties`, `minProperties`, `maxProperties` | ✅ | All validated in generated code |
| Enum | `enum` | ✅ | String enums → Crystal enum; numeric enums → runtime validation |
| Composition | `allOf`, `oneOf`, `anyOf`, `not` | ⚠️ | `allOf` → struct/class (multi-ref merge) or type alias (single $ref); `oneOf`/`anyOf` with all $refs → typed wrapper struct; single $ref → type alias; mixed inline+ref → `JSON::Any`; `not` → untranslatable in Crystal's type system (documented ❌) |
| OAS extensions | `nullable`, `readOnly`, `writeOnly`, `deprecated`, `discriminator`, `xml`, `externalDocs` | ✅ | `nullable`/`discriminator`/`xml`/`readOnly`/`writeOnly`/`deprecated` used; `externalDocs` parsed only |

---

## Type Generator

| Capability | Status | Notes |
|---|:---:|---|
| Object → struct (value type) | ✅ | Default for non-error schemas |
| Object → class (reference type) | ✅ | Error responses; also via hook classification |
| Abstract class + discriminator | ✅ | `use_json_discriminator` emitted |
| Enum (string) | ✅ | `openapi_enum` macro with wire-value mapping |
| Extensible enum (`x-extensible-enum`) | ✅ | `openapi_extensible_enum` macro |
| Scalar type alias | ✅ | |
| Array alias | ✅ | |
| Hash alias (pure `additionalProperties`) | ✅ | |
| `allOf` single-parent inheritance | ✅ | |
| `oneOf` / `anyOf` typed unions | ⚠️ | All-$ref variants → typed wrapper struct with try-each `JSON::PullParser` deserialization; single $ref → type alias; discriminator → `AbstractClass` (unchanged); mixed inline+ref → `JSON::Any` alias |
| Inline operation request/response types | ✅ | Auto-named from `operationId` |
| Inline parameter enum types | ✅ | Auto-named from `param.name` |
| Validation helpers (property-level) | ✅ | `min/maxLength`, `pattern`, `min/max` (with exclusive bounds), `multipleOf`, `uniqueItems`, `min/maxProperties`, `enum` |
| `readOnly` enforcement | ✅ | Field is `T?`; server parse helpers call `strip_read_only!` to zero it out on ingress |
| `writeOnly` enforcement | ✅ | Field is `T?`; server response helpers call `strip_write_only!` to zero it out on egress |
| JSON serialization | ✅ | `JSON::Serializable` |
| YAML serialization | ✅ | `YAML::Serializable` |
| XML serialization | ✅ | Custom `OpenAPI::XML::Serializable` |
| Form serialization | ✅ | `OpenAPI::Form::Serializable` |
| UUID, URI format types | ✅ | Mapped to Crystal stdlib types |
| Format-to-type mapping | ✅ | Comprehensive `SCALAR_MAP` |

---

## Client Generator

| Capability | Status | Notes |
|---|:---:|---|
| Path parameters | ✅ | URL interpolation |
| Query parameters | ✅ | `HTTP::Params` builder |
| Header parameters | ✅ | Grouped into `headers` named-tuple param; response headers returned as tuple |
| Cookie parameters | ✅ | Grouped into `cookies` named-tuple param |
| JSON request/response | ✅ | |
| YAML request/response | ✅ | |
| XML request/response | ✅ | |
| Form-urlencoded request | ✅ | |
| Multipart/form-data | ✅ | Structured via `OpenAPI::Multipart::Serializable`; `format: binary` fields → `IO::Memory`; scalar fields → text parts; nested objects → JSON-encoded parts |
| Multi-content-type negotiation | ✅ | `content_type`/`accept` params added |
| Typed error responses (specific codes) | ✅ | |
| `default` error response | ✅ | |
| Wildcard range responses (`4XX`, etc.) | ✅ | `NXX` ranges mapped to representative status codes; client emits `400..499` range expressions in `case`; server maps to base code in rescue clause |
| `style`/`explode` parameter serialization | ✅ | Array query params: `form`+explode (multi-key), `form`/`spaceDelimited`/`pipeDelimited` (joined); scalar params unchanged; path `label`/`matrix` and `deepObject` not supported |
| Security/auth header injection | ➖ | Intentionally delegated to the application layer — inject credentials in the `perform_request` hook |
| `@[Deprecated]` on deprecated operations | ✅ | |
| Callback handling | ➖ | Callbacks are parsed (`Operation#callbacks`); the server calls your callback URL at runtime — implement a plain HTTP handler at whatever path your service exposes as the callback endpoint |
| `operationId`-derived method names | ✅ | Fallback: `{method}_{path_segments}` |
| Param validation at call site | ✅ | Optional via `ctx.validate_params` |

---

## Server Generator

| Capability | Status | Notes |
|---|:---:|---|
| Route registration (Kemal) | ✅ | |
| Route registration (HTTP::Server mux) | ✅ | |
| Abstract handler pattern | ✅ | Implementors override one method per operation |
| `around_action` hook | ✅ | Wraps every dispatch |
| Path parameter extraction + typing | ✅ | |
| Query parameter extraction + typing | ✅ | |
| Header parameter extraction | ✅ | Grouped into `headers` named-tuple arg; extracted in route handler and passed to abstract def |
| Cookie parameter extraction | ✅ | Grouped into `cookies` named-tuple arg; extracted in route handler and passed to abstract def |
| JSON body parsing | ✅ | |
| YAML body parsing | ✅ | |
| XML body parsing | ✅ | |
| Form-urlencoded body parsing | ✅ | |
| Multipart/form-data parsing | ✅ | Structured via `T.from_multipart(request)` using `HTTP::FormData.parse`; `parse_multipart_body` helper in generated handler |
| Typed error rescue blocks | ✅ | |
| `validate_params` method | ✅ | Optional |
| Path-item-level parameters | ✅ | Merged with operation parameters; operation params with the same `name`+`in` override path-item defaults |
| Security middleware | ➖ | Intentionally delegated to the application layer — implement auth checks in the `around_action` hook |
| `@[Deprecated]` on deprecated operations | ✅ | |

---

## Reference Resolution

| Scenario | Status | Notes |
|---|:---:|---|
| Internal `$ref` (`#/components/schemas/Foo`) | ✅ | Name extracted; value walked in generators |
| Internal `$ref` (`#/components/responses/...`) | ✅ | Resolved in error-type generation |
| Internal `$ref` on Path Item | ✅ | Resolved via `Document#each_path_item`; external file refs explicitly not supported (security) |
| External file `$ref` (`Pet.yaml`) | ➖ | Explicitly not supported — loading arbitrary external files poses a path-traversal / SSRF risk; use `Document.merge` instead |
| External file + JSON Pointer (`defs.json#/Pet`) | ➖ | Explicitly not supported — same security rationale; pre-merge files before passing to the generator |
| Multi-document merge (separate files loaded by caller) | ✅ | Via `Document.merge` |

---

## Specification Extensions (x-*)

| Category | Status | Notes |
|---|:---:|---|
| Unknown `x-` fields (ignored gracefully) | ✅ | Crystal serializers skip unknown keys |
| Redocly extensions (`x-nullable`, `x-extensible-enum`, `x-enumDescriptions`) | ✅ | Actively used in type generation |
| Documentation extensions (`x-tagGroups`, `x-logo`, `x-badges`, `x-codeSamples`, etc.) | ✅ | Parsed on relevant objects |
| Custom type hook extensions (`x-additionalPropertiesName`, `x-rbac`) | ✅ | Parsed |
| OAuth extensions (`x-usePkce`, `x-assertionType`) | ✅ | Parsed |
| Webhook support (`x-webhooks`) | ✅ | Parsed as `Hash(String, PathItem)`; not code-generated |
