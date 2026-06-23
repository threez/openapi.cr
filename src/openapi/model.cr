require "yaml"
require "json"

module OpenAPI
  module Model
    # Forward declaration to break the Operation <-> PathItem circular reference.
    # PathItem is fully defined in model/path_item.cr, which is required below.
    class PathItem; end
  end
end

require "./model/any_converter"
require "./model/number_converter"
require "./model/or_ref"
require "./model/extensions"
require "./model/external_docs"
require "./model/discriminator"
require "./model/xml"
require "./model/schema"
require "./model/example"
require "./model/encoding"
require "./model/header"
require "./model/media_type"
require "./model/link"
require "./model/info"
require "./model/server"
require "./model/tag"
require "./model/parameter"
require "./model/request_body"
require "./model/response"
require "./model/operation"
require "./model/path_item"
require "./model/security_scheme"
require "./model/components"
require "./model/document"
