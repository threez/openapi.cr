module OpenAPI
  module Validation
    # A single constraint violation detected by a generated type's `valid?` method.
    struct Error
      getter field : String
      getter value : String
      getter message : String
      getter constraint : String
      getter constraint_value : String

      def initialize(
        @field : String,
        @value : String,
        @message : String,
        @constraint : String,
        @constraint_value : String,
      )
      end

      def to_s(io : IO) : Nil
        io << @message
      end
    end

    # Raised by generated types' `validate!` method when validation fails.
    # Access individual violations via `errors`.
    class Exception < ::Exception
      getter errors : Array(Error)

      def initialize(@errors : Array(Error))
        super(@errors.map(&.message).join("; "))
      end
    end
  end
end
