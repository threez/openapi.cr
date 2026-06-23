module OpenAPI
  module Generator
    # Generates an abstract Kemal handler stub for each API operation.
    # The generated `Handler` class uses `KemalHelpers` for request/response helpers.
    class KemalServerGenerator < ServerGenerator
      private def framework_require : String
        "kemal"
      end

      private def context_var : String
        "env"
      end

      private def helpers_module : String
        "OpenAPI::Server::KemalHelpers"
      end

      private def route_prefix(http_method : String) : String
        http_method
      end

      private def register_def : String
        "def register : Nil"
      end

      private def path_param_key(name : String) : String
        name.inspect
      end

      private def before_action_context_type : String
        "HTTP::Server::Context"
      end

      private def wrap_handler(b : Crystina::Builder, &block : Crystina::Builder ->) : Nil
        b.scope("module Kemal") do |inner|
          block.call(inner)
        end
      end
    end
  end
end
