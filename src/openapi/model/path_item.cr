module OpenAPI
  module Model
    # The set of HTTP operations available on a single path.
    class PathItem
      include YAML::Serializable
      include JSON::Serializable

      @[YAML::Field(key: "$ref")]
      @[JSON::Field(key: "$ref")]
      getter ref : String? = nil

      getter summary : String? = nil
      getter description : String? = nil

      getter get : Operation? = nil
      getter put : Operation? = nil
      getter post : Operation? = nil
      getter delete : Operation? = nil
      getter options : Operation? = nil
      getter head : Operation? = nil
      getter patch : Operation? = nil
      getter trace : Operation? = nil

      getter servers : Array(Server)? = nil
      getter parameters : Array(OrRef(Parameter))? = nil

      # Returns `true` when this path item is a `$ref` pointer rather than an inline definition.
      def ref? : Bool
        !@ref.nil?
      end

      # Yields each HTTP method's operation that is present.
      def each_operation(&block : String, Operation ->)
        if op = @get
          block.call("get", op)
        end
        if op = @put
          block.call("put", op)
        end
        if op = @post
          block.call("post", op)
        end
        if op = @delete
          block.call("delete", op)
        end
        if op = @options
          block.call("options", op)
        end
        if op = @head
          block.call("head", op)
        end
        if op = @patch
          block.call("patch", op)
        end
        if op = @trace
          block.call("trace", op)
        end
      end
    end
  end
end
