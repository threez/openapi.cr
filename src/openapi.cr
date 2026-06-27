require "./openapi/macro/enum"
require "./openapi/macro/union"
require "./openapi/macro/allof"
require "./openapi/macro/exception"
require "./openapi/validation/error"
require "./openapi/validation/helpers"
require "./openapi/client/helpers"
require "./openapi/server/helpers"
require "./openapi/server/mux_helpers"
require "./openapi/server/kemal_helpers"
require "./openapi/model"
require "./openapi/generator"

# OpenAPI 3.x document model, generator, and runtime helpers for Crystal.
#
# Three layers:
# - `OpenAPI::Model` — deserializable structs that mirror the OpenAPI 3.x spec.
# - `OpenAPI::Generator` — code generators that produce Crystal client/server files.
# - `OpenAPI::Validation` and server helpers — runtime support for generated code.
module OpenAPI
  # Library version.
  VERSION = "0.1.1"
end
