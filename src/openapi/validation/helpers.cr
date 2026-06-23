module OpenAPI
  module Validation
    # Validation helper methods mixed into generated types that declare constraints.
    # The generator emits the `include` automatically; you may also include it
    # manually in types that wrap or extend generated code.
    module Helpers
      private def validate_required(errors : Array(Error), field : String, value) : Nil
        errors << Error.new(field, "", "#{field} is required", "required", "true") if value.nil?
      end

      private def validate_min_length(errors : Array(Error), field : String, value : String?, min : Int) : Nil
        return unless value
        errors << Error.new(field, value, "#{field} length #{value.size} is below minLength #{min}", "minLength", min.to_s) if value.size < min
      end

      private def validate_max_length(errors : Array(Error), field : String, value : String?, max : Int) : Nil
        return unless value
        errors << Error.new(field, value, "#{field} length #{value.size} exceeds maxLength #{max}", "maxLength", max.to_s) if value.size > max
      end

      private def validate_pattern(errors : Array(Error), field : String, value : String?, pattern : Regex, pattern_str : String) : Nil
        return unless value
        errors << Error.new(field, value, "#{field} \"#{value}\" does not match pattern \"#{pattern_str}\"", "pattern", pattern_str) unless value.matches?(pattern)
      end

      private def validate_minimum(errors : Array(Error), field : String, value : T?, min : T, exclusive : Bool = false) : Nil forall T
        return unless value
        fails = exclusive ? value <= min : value < min
        msg = exclusive ? "must be greater than #{min} (exclusive)" : "is below minimum #{min}"
        errors << Error.new(field, value.to_s, "#{field} #{value} #{msg}", "minimum", min.to_s) if fails
      end

      private def validate_maximum(errors : Array(Error), field : String, value : T?, max : T, exclusive : Bool = false) : Nil forall T
        return unless value
        fails = exclusive ? value >= max : value > max
        msg = exclusive ? "must be less than #{max} (exclusive)" : "exceeds maximum #{max}"
        errors << Error.new(field, value.to_s, "#{field} #{value} #{msg}", "maximum", max.to_s) if fails
      end

      private def validate_multiple_of(errors : Array(Error), field : String, value : T?, divisor : T) : Nil forall T
        return unless value
        errors << Error.new(field, value.to_s, "#{field} #{value} is not a multiple of #{divisor}", "multipleOf", divisor.to_s) unless (value % divisor).zero?
      end

      private def validate_unique_items(errors : Array(Error), field : String, value : Array(T)?) : Nil forall T
        return unless value
        errors << Error.new(field, value.size.to_s, "#{field} must contain unique items", "uniqueItems", "true") if value.uniq.size != value.size
      end

      private def validate_min_items(errors : Array(Error), field : String, value : Array(T)?, min : Int) : Nil forall T
        return unless value
        errors << Error.new(field, value.size.to_s, "#{field} has #{value.size} items, minimum is #{min}", "minItems", min.to_s) if value.size < min
      end

      private def validate_max_items(errors : Array(Error), field : String, value : Array(T)?, max : Int) : Nil forall T
        return unless value
        errors << Error.new(field, value.size.to_s, "#{field} has #{value.size} items, maximum is #{max}", "maxItems", max.to_s) if value.size > max
      end

      private def validate_min_properties(errors : Array(Error), field : String, value : Hash(K, V)?, min : Int) : Nil forall K, V
        return unless value
        errors << Error.new(field, value.size.to_s, "#{field} has #{value.size} properties, minimum is #{min}", "minProperties", min.to_s) if value.size < min
      end

      private def validate_max_properties(errors : Array(Error), field : String, value : Hash(K, V)?, max : Int) : Nil forall K, V
        return unless value
        errors << Error.new(field, value.size.to_s, "#{field} has #{value.size} properties, maximum is #{max}", "maxProperties", max.to_s) if value.size > max
      end

      private def validate_enum(errors : Array(Error), field : String, value : T, allowed : Array(T)) : Nil forall T
        return if allowed.includes?(value)
        allowed_str = allowed.map(&.to_s).join(", ")
        errors << Error.new(field, value.inspect, "#{field} \"#{value}\" is not one of #{allowed_str}", "enum", allowed_str)
      end
    end
  end
end
