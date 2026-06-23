module OpenAPI
  module Generator
    module Types
      # :nodoc:
      module NameInflector
        RESERVED_WORDS = Set{
          "abstract", "alias", "as", "asm", "begin", "break", "case", "class",
          "def", "do", "else", "elsif", "end", "ensure", "enum", "extend",
          "false", "for", "fun", "if", "in", "include", "lib", "macro",
          "module", "next", "nil", "of", "out", "pointerof", "private",
          "protected", "require", "rescue", "return", "select", "self",
          "sizeof", "struct", "super", "then", "true", "type", "typeof",
          "union", "unless", "until", "when", "while", "with", "yield",
        }

        def self.snake_case(str : String) : String
          str
            .gsub(/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
            .gsub(/([a-z\d])([A-Z])/, "\\1_\\2")
            .gsub(/[-\s]+/, "_")
            .gsub(/[^a-zA-Z0-9_]/, "_")
            .downcase
        end

        def self.pascal_case(str : String) : String
          snake_case(str).split('_').map { |w|
            w.empty? ? w : w[0].upcase.to_s + w[1..]
          }.join
        end

        def self.safe_identifier(str : String) : String
          result = str.gsub(/[^a-zA-Z0-9_]/, "_")
          result = "v#{result}" if result[0]?.try(&.ascii_number?)
          RESERVED_WORDS.includes?(result) ? "_#{result}" : result
        end

        def self.allof_part_name(parent : String, index : Int32) : String
          index == 0 ? "#{parent}Merged" : "#{parent}Merged#{index + 1}"
        end

        def self.operation_error_type_name(operation_id : String?, http_method : String, path_template : String, status_key : String) : String
          base = operation_type_name(operation_id, http_method, path_template)
          status_key == "default" ? "#{base}Error" : "#{base}Error#{status_key}"
        end

        def self.operation_type_name(operation_id : String?, http_method : String, path_template : String) : String
          if op_id = operation_id
            pascal_case(snake_case(op_id))
          else
            parts = path_template.split("/").compact_map do |segment|
              next nil if segment.empty?
              if segment.starts_with?('{') && segment.ends_with?('}')
                "by_#{snake_case(segment[1..-2])}"
              else
                snake_case(segment)
              end
            end
            pascal_case(safe_identifier("#{http_method}_#{parts.join("_")}"))
          end
        end
      end
    end
  end
end
