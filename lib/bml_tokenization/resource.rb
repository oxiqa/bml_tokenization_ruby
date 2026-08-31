# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module BmlTokenization
  # Base HTTP/JSON request-response behavior shared by every resource.
  #
  # Builds the request against the client's configured base URL, injects the
  # client's auth headers, enforces TLS-only transport, parses the JSON body,
  # and dispatches non-2xx responses to the mapped error hierarchy (FR-009).
  # Transport failures/timeouts map to {AvailabilityError} with no partial
  # record (edge case).
  class Resource
    JSON_HEADERS = {
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }.freeze

    def initialize(client)
      @client = client
    end

    attr_reader :client

    # Perform an HTTP request and return the parsed response body (for 2xx).
    #
    # method:: one of :get, :post, :put
    # path::   request path relative to the client base URL (e.g. "/customers")
    # params:: query parameters (Hash) — used for list pagination
    # body::   request body (Hash) serialized as JSON
    def request(method, path, params: nil, body: nil)
      uri = build_uri(path, params)
      enforce_tls!(uri)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"

      response = http.request(build_request(method, uri, body))
      handle_response(response)
    rescue Timeout::Error,
           Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
           SocketError, IOError => e
      raise AvailabilityError, "BML platform unavailable: #{e.class}"
    end

    private

    def build_uri(path, params)
      uri = URI.join(ensure_trailing_slash(client.base_url), path.sub(%r{\A/}, ""))
      uri.query = URI.encode_www_form(compact(params)) if params && !params.empty?
      uri
    end

    def ensure_trailing_slash(base)
      base.end_with?("/") ? base : "#{base}/"
    end

    def compact(params)
      (params || {}).reject { |_, v| v.nil? }
    end

    def enforce_tls!(uri)
      return if uri.scheme == "https"

      raise ConfigurationError, "Refusing to send a request over a non-TLS URL (#{uri.scheme})"
    end

    def build_request(method, uri, body)
      request_class =
        case method
        when :get then Net::HTTP::Get
        when :post then Net::HTTP::Post
        when :put then Net::HTTP::Put
        else raise ArgumentError, "Unsupported HTTP method: #{method}"
        end

      req = request_class.new(uri)
      apply_headers(req)
      req.body = JSON.generate(body) if body
      req
    end

    def apply_headers(req)
      JSON_HEADERS.each { |key, value| req[key] = value }
      client.auth_headers.each { |key, value| req[key] = value }
    end

    def handle_response(response)
      code = response.code.to_i
      body = parse_body(response.body)

      case code
      when 200..299
        body
      when 400, 422
        raise ValidationError.new(error_message(body, "Invalid request"), field: field_from(body))
      when 401, 403
        raise AuthenticationError, error_message(body, "Authentication or configuration error")
      when 404
        raise NotFoundError, error_message(body, "Resource not found")
      when 409
        raise ConflictError, error_message(body, "Conflict with existing resource")
      when 408, 500..599
        raise AvailabilityError, error_message(body, "BML platform unavailable")
      else
        raise Error, error_message(body, "Unexpected response (HTTP #{code})")
      end
    end

    def parse_body(raw)
      return {} if raw.nil? || raw.empty?

      JSON.parse(raw)
    rescue JSON::ParserError
      {}
    end

    def error_message(body, fallback)
      return fallback unless body.is_a?(Hash)

      body["message"] || body["error"] || fallback
    end

    def field_from(body)
      return nil unless body.is_a?(Hash)

      value = body["field"] || body["param"]
      value&.to_sym
    end
  end
end
