# frozen_string_literal: true

module BmlTokenization
  # Immutable, masked representation of a stored card, returned by tokenize and
  # retrieve (data-model.md Token). A token is exposed only as a platform-assigned
  # safe, non-reversible +reference+ (FR-006) plus a masked summary (scheme,
  # +last4+, expiry) and a validity +status+ (FR-004).
  #
  # Forbidden fields — full PAN, CVV/CVV2, track data, PIN, the single-use card
  # handle, or any SAD — cannot exist here by construction: only the whitelisted
  # {ATTRIBUTES} are retained, so anything else the platform returns is dropped
  # (FR-003, FR-006a, FR-013). +inspect+/+to_s+/+to_h+ render only those masked
  # fields so nothing sensitive can leak through logging or serialization (R7).
  class Token
    # Valid lifecycle states (data-model.md state transitions).
    STATUSES = %w[active revoked expired].freeze

    # The complete, exhaustive attribute set. +last4+ is the only PAN fragment
    # ever exposed (FR-003). +environment+ is informational, sourced from client
    # config, and never a secret (FR-008).
    ATTRIBUTES = %i[
      reference scheme last4 expiry_month expiry_year status account_scope environment
    ].freeze

    attr_reader(*ATTRIBUTES)

    def initialize(attributes = {})
      normalized = symbolize(attributes)
      ATTRIBUTES.each do |name|
        instance_variable_set("@#{name}", normalized[name])
      end
    end

    # Build a Token from a remote response hash, ignoring any unknown or
    # sensitive keys the platform might return. The platform names the safe
    # identifier +token_reference+; a plain +reference+ is also accepted. The
    # owning +environment+ is injected from the client config (never parsed from
    # the wire) so a token always reports the environment it belongs to (FR-008).
    def self.from_response(hash, environment: nil)
      data = (hash || {}).each_with_object({}) do |(key, value), acc|
        acc[key.to_s] = value
      end
      new(
        reference: data["token_reference"] || data["reference"],
        scheme: data["scheme"],
        last4: data["last4"],
        expiry_month: data["expiry_month"],
        expiry_year: data["expiry_year"],
        status: data["status"],
        account_scope: data["account_scope"],
        environment: environment
      )
    end

    def active?
      status.to_s == "active"
    end

    def revoked?
      status.to_s == "revoked"
    end

    def expired?
      status.to_s == "expired"
    end

    # Serialization is limited to the whitelisted attributes only.
    def to_h
      ATTRIBUTES.each_with_object({}) do |name, acc|
        acc[name] = public_send(name)
      end
    end

    def ==(other)
      other.is_a?(Token) && other.to_h == to_h
    end
    alias eql? ==

    def hash
      to_h.hash
    end

    def inspect
      pairs = to_h.reject { |_, v| v.nil? }.map { |k, v| "#{k}=#{v.inspect}" }
      "#<BmlTokenization::Token #{pairs.join(' ')}>"
    end
    alias to_s inspect

    private

    def symbolize(attributes)
      (attributes || {}).each_with_object({}) do |(key, value), acc|
        acc[key.to_sym] = value
      end
    end
  end
end
