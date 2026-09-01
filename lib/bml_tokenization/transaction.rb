# frozen_string_literal: true

module BmlTokenization
  # Immutable payment record returned by create and retrieve, and as elements of
  # a list page (data-model.md, FR-002/FR-003/FR-006).
  #
  # Only the whitelisted attributes below are ever exposed. A created transaction
  # is characterized by exactly one completion route: +payment_url+ (redirect
  # path) or +card_reference+ (stored-card path) (R3). +status+ is normalized to
  # one of the four canonical values (FR-006, R6).
  #
  # Forbidden fields — full PAN, CVV/CVV2, track data, PIN, or any SAD — cannot
  # exist here by construction: anything outside {ATTRIBUTES} the platform returns
  # is dropped (FR-010, SC-005).
  class Transaction
    # The complete, exhaustive attribute set exposed to callers.
    ATTRIBUTES = %i[
      id reference customer_id amount currency status
      payment_url card_reference return_url created_at
    ].freeze

    # The four canonical, distinguishable statuses (FR-006, R6).
    STATUSES = %w[pending succeeded failed cancelled].freeze

    # Conservative normalization of the platform's raw status to a canonical
    # value. The four canonical values pass through; common synonyms are folded;
    # an unrecognized value is returned lower-cased rather than guessed.
    STATUS_ALIASES = {
      "pending" => "pending", "processing" => "pending", "initiated" => "pending",
      "created" => "pending", "in_progress" => "pending",
      "succeeded" => "succeeded", "success" => "succeeded", "successful" => "succeeded",
      "paid" => "succeeded", "completed" => "succeeded", "captured" => "succeeded",
      "failed" => "failed", "failure" => "failed", "declined" => "failed", "error" => "failed",
      "cancelled" => "cancelled", "canceled" => "cancelled", "cancel" => "cancelled",
      "voided" => "cancelled", "abandoned" => "cancelled"
    }.freeze

    attr_reader(*ATTRIBUTES)

    def initialize(attributes = {})
      normalized = symbolize(attributes)
      ATTRIBUTES.each do |name|
        instance_variable_set("@#{name}", normalized[name])
      end
      @status = normalize_status(@status)
    end

    # Build a Transaction from a remote response hash, ignoring any unknown or
    # sensitive keys the platform might return.
    def self.from_response(hash)
      new(hash || {})
    end

    # Serialization is limited to the whitelisted attributes only.
    def to_h
      ATTRIBUTES.each_with_object({}) do |name, acc|
        acc[name] = public_send(name)
      end
    end

    def ==(other)
      other.is_a?(Transaction) && other.to_h == to_h
    end
    alias eql? ==

    def hash
      to_h.hash
    end

    def inspect
      pairs = to_h.reject { |_, v| v.nil? }.map { |k, v| "#{k}=#{v.inspect}" }
      "#<BmlTokenization::Transaction #{pairs.join(' ')}>"
    end

    private

    def normalize_status(raw)
      return nil if raw.nil?

      key = raw.to_s.strip.downcase
      STATUS_ALIASES.fetch(key, key)
    end

    def symbolize(attributes)
      (attributes || {}).each_with_object({}) do |(key, value), acc|
        acc[key.to_sym] = value
      end
    end
  end
end
