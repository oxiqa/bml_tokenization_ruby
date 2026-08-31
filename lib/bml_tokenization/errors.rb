# frozen_string_literal: true

module BmlTokenization
  # Base class for every error raised by the library. Callers can rescue this
  # to catch any library error, or rescue a specific subclass to branch on the
  # mapped condition (FR-009).
  class Error < StandardError; end

  # A required input was missing or invalid. Raised locally before any remote
  # call (FR-006) or when the platform reports an invalid field. Always names
  # the offending field via {#field} where one applies (SC-003).
  class ValidationError < Error
    attr_reader :field

    def initialize(message = nil, field: nil)
      @field = field
      super(message)
    end
  end

  # A referenced resource (e.g. a customer identifier) does not exist.
  class NotFoundError < Error; end

  # The request conflicts with platform state, e.g. a duplicate customer per
  # the platform's uniqueness rules. Carries the parsed response {#body} when
  # present so a caller (e.g. an idempotent store) can recover an existing
  # reference the platform returned alongside the conflict (FR-013, R5).
  class ConflictError < Error
    attr_reader :body

    def initialize(message = nil, body: nil)
      @body = body
      super(message)
    end
  end

  # Missing/invalid credentials or client configuration (auth/config). Distinct
  # from a validation error so callers can react to a setup problem (FR-008).
  class AuthenticationError < Error; end

  # Configuration problem detected before a request is attempted (e.g. an
  # unknown environment or a non-TLS base URL). A specialization of the
  # auth/config category.
  class ConfigurationError < AuthenticationError; end

  # The remote platform was unavailable or timed out. No partial record is
  # returned when this is raised (edge case). Treated as transient by the
  # shared transport concern and retried within the bounded budget (FR-014).
  class AvailabilityError < Error; end

  # The platform rate-limited the request ("too many requests" / 429) and was
  # still rate-limiting after the bounded retry budget was exhausted (FR-014,
  # R7). Distinct from {AvailabilityError} so callers can apply their own
  # longer-term backoff. Carries the server's {#retry_after} hint (seconds)
  # when one was supplied.
  class RateLimitError < Error
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil)
      @retry_after = retry_after
      super(message)
    end
  end
end
