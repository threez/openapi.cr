require "http/formdata"

module OpenAPI
  module Server
    # Shared request/response helpers included by both MuxHelpers and KemalHelpers.
    # Not intended for direct inclusion — use the framework-specific module instead.
    module Helpers
      # Wraps every generated route handler. Override in a subclass to add
      # logging, auth, timing, or any other cross-cutting behaviour.
      # Call `yield` (or `previous_def`) to execute the actual dispatch.
      # Raise an exception to abort without dispatching.
      def around_action(operation : Symbol, context, & : -> Nil) : Nil
        yield
      end

      private def json_response(ctx, status : Int32, body) : Nil
        body.strip_write_only! if body.responds_to?(:strip_write_only!)
        ctx.response.status_code = status
        ctx.response.content_type = "application/json"
        ctx.response.print body.to_json
      end

      private def yaml_response(ctx, status : Int32, body) : Nil
        body.strip_write_only! if body.responds_to?(:strip_write_only!)
        ctx.response.status_code = status
        ctx.response.content_type = "application/yaml"
        ctx.response.print body.to_yaml
      end

      private def xml_response(ctx, status : Int32, body) : Nil
        body.strip_write_only! if body.responds_to?(:strip_write_only!)
        ctx.response.status_code = status
        ctx.response.content_type = "application/xml"
        ctx.response.print body.to_xml
      end

      # Serializes body as JSON (default) or YAML depending on the Accept
      # header. Only uses YAML when the Accept header explicitly requests it
      # and does not include "json".
      private def typed_response(ctx, status : Int32, body) : Nil
        body.strip_write_only! if body.responds_to?(:strip_write_only!)
        ctx.response.status_code = status
        accept = ctx.request.headers["Accept"]?
        if accept && accept.includes?("yaml") && !accept.includes?("json")
          ctx.response.content_type = "application/yaml"
          ctx.response.print body.to_yaml
        else
          ctx.response.content_type = "application/json"
          ctx.response.print body.to_json
        end
      end

      # Serializes body as JSON (default) or XML depending on the Accept header.
      # Used for operations that support JSON and XML but not YAML.
      private def xml_json_typed_response(ctx, status : Int32, body) : Nil
        body.strip_write_only! if body.responds_to?(:strip_write_only!)
        ctx.response.status_code = status
        accept = ctx.request.headers["Accept"]?
        if accept && accept.includes?("xml")
          ctx.response.content_type = "application/xml"
          ctx.response.print body.to_xml
        else
          ctx.response.content_type = "application/json"
          ctx.response.print body.to_json
        end
      end

      private def parse_json_body(ctx, type : T.class) : T forall T
        result = T.from_json(ctx.request.body.try(&.gets_to_end) || "")
        result.strip_read_only! if result.responds_to?(:strip_read_only!)
        result
      end

      private def parse_xml_body(ctx, type : T.class) : T forall T
        result = T.from_xml(ctx.request.body.try(&.gets_to_end) || "")
        result.strip_read_only! if result.responds_to?(:strip_read_only!)
        result
      end

      # Parses the request body as JSON (default), YAML, or form-urlencoded
      # depending on the Content-Type header. JSON is preferred: YAML is only
      # used when Content-Type includes "yaml" but not "json"; form is used when
      # Content-Type includes "x-www-form-urlencoded".
      private def parse_body(ctx, type : T.class) : T forall T
        raw = ctx.request.body.try(&.gets_to_end) || ""
        ct = ctx.request.headers["Content-Type"]?
        result = if ct && ct.includes?("yaml") && !ct.includes?("json")
                   T.from_yaml(raw)
                 elsif ct && ct.includes?("x-www-form-urlencoded")
                   T.from_form_params(HTTP::Params.parse(raw))
                 else
                   T.from_json(raw)
                 end
        result.strip_read_only! if result.responds_to?(:strip_read_only!)
        result
      end

      # Parses the request body as JSON (default) or XML depending on Content-Type.
      # Used for operations that support JSON and XML but not YAML or form encoding.
      private def xml_json_parse_body(ctx, type : T.class) : T forall T
        raw = ctx.request.body.try(&.gets_to_end) || ""
        ct = ctx.request.headers["Content-Type"]?
        result = if ct && ct.includes?("xml")
                   T.from_xml(raw)
                 else
                   T.from_json(raw)
                 end
        result.strip_read_only! if result.responds_to?(:strip_read_only!)
        result
      end

      private def parse_form_body(ctx, type : T.class) : T forall T
        result = T.from_form_params(HTTP::Params.parse(ctx.request.body.try(&.gets_to_end) || ""))
        result.strip_read_only! if result.responds_to?(:strip_read_only!)
        result
      end

      private def parse_multipart_body(ctx, type : T.class) : T forall T
        result = T.from_multipart(ctx.request)
        result.strip_read_only! if result.responds_to?(:strip_read_only!)
        result
      end

      private def raw_body(ctx) : IO::Memory
        IO::Memory.new(ctx.request.body.try(&.gets_to_end) || "")
      end

      private def raw_response(ctx, status : Int32, body : IO::Memory, content_type : String = "text/plain") : Nil
        ctx.response.status_code = status
        ctx.response.content_type = content_type
        ctx.response.print body.rewind.gets_to_end
      end

      private def json_error(ctx, ex, status : Int32) : Nil
        ctx.response.status_code = status
        ctx.response.content_type = "application/json"
        ctx.response.print ex.to_json
      end

      private def header_string(ctx, name : String) : String?
        ctx.request.headers[name]?
      end

      private def header_int32(ctx, name : String) : Int32?
        ctx.request.headers[name]?.try(&.to_i32?)
      end

      private def header_int64(ctx, name : String) : Int64?
        ctx.request.headers[name]?.try(&.to_i64?)
      end

      private def header_float32(ctx, name : String) : Float32?
        ctx.request.headers[name]?.try(&.to_f32?)
      end

      private def header_float64(ctx, name : String) : Float64?
        ctx.request.headers[name]?.try(&.to_f64?)
      end

      private def header_bool(ctx, name : String) : Bool?
        ctx.request.headers[name]?.try { |v| v == "true" }
      end

      private def cookie_string(ctx, name : String) : String?
        ctx.request.cookies[name]?.try(&.value)
      end

      private def cookie_int32(ctx, name : String) : Int32?
        ctx.request.cookies[name]?.try(&.value).try(&.to_i32?)
      end

      private def cookie_int64(ctx, name : String) : Int64?
        ctx.request.cookies[name]?.try(&.value).try(&.to_i64?)
      end

      private def cookie_float32(ctx, name : String) : Float32?
        ctx.request.cookies[name]?.try(&.value).try(&.to_f32?)
      end

      private def cookie_float64(ctx, name : String) : Float64?
        ctx.request.cookies[name]?.try(&.value).try(&.to_f64?)
      end

      private def cookie_bool(ctx, name : String) : Bool?
        ctx.request.cookies[name]?.try(&.value).try { |v| v == "true" }
      end
    end
  end
end
