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
      production: "https://api.merchants.bankofmaldives.com.mv"
    }.freeze

    # Default per-request timeout (seconds) and bounded-retry policy applied by
    # the shared transport concern (FR-014). Overridable at construction.
    DEFAULT_TIMEOUT = 30
    DEFAULT_MAX_RETRIES = 2
    DEFAULT_RETRY_BACKOFF = 0.5

    attr_reader :environment, :base_url, :api_key, :app_id, :logger,
                :timeout, :max_retries, :retry_backoff, :audit_sink

    # api_key/app_id::  credentials injected on every request (FR-008).
    # environment::     :sandbox (default) or :production.
    # base_url::        optional override (must be https); otherwise derived.
    # logger::          optional logger for structured, masked log lines.
    # timeout::         per-request timeout in seconds (FR-014).
    # max_retries::     transient-failure retries after the first attempt (FR-014).
    # retry_backoff::   base backoff seconds between retries (FR-014).
    # audit_sink::      optional sink (responding to #call or #<<) receiving the
    #                   audit record emitted on state changes (FR-015).
    def initialize(api_key: nil, app_id: nil, environment: :sandbox, base_url: nil, logger: nil,
                   timeout: DEFAULT_TIMEOUT, max_retries: DEFAULT_MAX_RETRIES,
                   retry_backoff: DEFAULT_RETRY_BACKOFF, audit_sink: nil)
      @environment = environment.to_sym
      @api_key = api_key
      @app_id = app_id
      @base_url = base_url || default_base_url
      @logger = logger
      @timeout = timeout
      @max_retries = max_retries
      @retry_backoff = retry_backoff
      @audit_sink = audit_sink
    end

    # The Customers resource bound to this client (FR-001).
    def customers
      @customers ||= Customers.new(self)
    end

    # The CardsOnFile resource bound to this client (FR-001).
    def cards_on_file
      @cards_on_file ||= CardsOnFile.new(self)
    end

    # The Transactions resource bound to this client (FR-001, FR-007, FR-008).
    def transactions
      @transactions ||= Transactions.new(self)
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
