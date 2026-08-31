# frozen_string_literal: true

module BmlTokenization
  # Configured entry point to the BML platform.
  #
  # Holds the selected environment (sandbox/production), the base URL derived
  # from it, and the credentials injected on every request. Exposes per-resource
  # accessors (currently {#customers}). The same code path serves both
  # environments and never crosses between them (FR-007, Constitution III).
  class Client
    # Representative environment base URLs. The environment is selected at
    # construction and the base URL is derived from it, so a sandbox client can
    # never route to production or vice versa (SC-005).
    BASE_URLS = {
      sandbox: "https://api.uat.merchants.bankofmaldives.com.mv",
      production: "	https://api.merchants.bankofmaldives.com.mv"
    }.freeze

    attr_reader :environment, :base_url, :api_key, :app_id, :logger

    # api_key/app_id:: credentials injected on every request (FR-008).
    # environment::    :sandbox (default) or :production.
    # base_url::       optional override (must be https); otherwise derived.
    # logger::         optional logger for structured, masked log lines.
    def initialize(api_key: nil, app_id: nil, environment: :sandbox, base_url: nil, logger: nil)
      @environment = environment.to_sym
      @api_key = api_key
      @app_id = app_id
      @base_url = base_url || default_base_url
      @logger = logger
    end

    # The Customers resource bound to this client (FR-001).
    def customers
      @customers ||= Customers.new(self)
    end

    # Credential headers injected on every request. Never logged (FR-008).
    def auth_headers
      headers = {}
      headers["Authorization"] = "Bearer #{api_key}" if api_key
      headers["X-App-Id"] = app_id if app_id
      headers
    end

    private

    def default_base_url
      BASE_URLS.fetch(environment) do
        raise ConfigurationError,
              "Unknown environment #{environment.inspect}; expected :sandbox or :production"
      end
    end
  end
end
