module OpenAPI
  module Generator
    # Generates an abstract Mux router handler stub for each API operation.
    # The generated `Handler` class uses `MuxHelpers` for request/response helpers.
    class MuxServerGenerator < ServerGenerator
      private def framework_require : String
        "mux"
      end

      private def context_var : String
        "ctx"
      end

      private def helpers_module : String
        "OpenAPI::Server::MuxHelpers"
      end

      private def route_prefix(http_method : String) : String
        "mux.#{http_method}"
      end

      private def register_def : String
        "def register(mux : Mux::Router) : Nil"
      end

      private def path_param_key(name : String) : String
        ":#{name}"
      end

      private def before_action_context_type : String
        "Mux::Context"
      end
    end
  end
end
