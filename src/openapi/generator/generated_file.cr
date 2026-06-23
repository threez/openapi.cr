module OpenAPI
  module Generator
    # A generated source file represented as a path+content pair.
    record GeneratedFile, path : String, content : String do
      # Runs `crystal tool format` on the content and returns a new `GeneratedFile`
      # with the formatted result. Falls back to the original content on failure.
      # Requires `crystal` to be on `$PATH`.
      def format : GeneratedFile
        tmp = File.tempfile("openapi_gen", ".cr")
        tmp.print(content)
        tmp.flush
        tmp.close
        Process.run("crystal", ["tool", "format", tmp.path])
        GeneratedFile.new(path, File.read(tmp.path))
      ensure
        tmp.try { |f| File.delete(f.path) if File.exists?(f.path) }
      end

      # Returns true if the content is syntactically valid Crystal.
      def valid_syntax? : Bool
        tmp = File.tempfile("openapi_gen", ".cr")
        tmp.print(content)
        tmp.flush
        tmp.close
        Process.run("crystal", ["tool", "format", "--check", tmp.path]).success?
      ensure
        tmp.try { |f| File.delete(f.path) if File.exists?(f.path) }
      end
    end
  end
end
