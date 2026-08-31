# frozen_string_literal: true

require "time"

module BmlTokenization
  # Immutable stored-card record returned by store, retrieve, and (as elements)
  # list. A card is exposed only as a platform-assigned safe +reference+ plus a
  # masked summary (scheme, last four, expiry) and a validity status
  # (data-model.md, FR-003).
  #
  # Forbidden fields — full PAN, CVV/CVV2, track data, PIN, the single-use card
  # handle, or any SAD — cannot exist here by construction: only the whitelisted
  # {ATTRIBUTES} are retained, so anything else the platform returns is dropped.
  class CardOnFile
    # The complete, exhaustive attribute set. +last_four+ is the only PAN
    # fragment ever exposed (FR-003).
    ATTRIBUTES = %i[
      reference customer_id scheme last_four expiry_month expiry_year status created_at
    ].freeze

    attr_reader(*ATTRIBUTES)

    def initialize(attributes = {})
      normalized = symbolize(attributes)
      ATTRIBUTES.each do |name|
        instance_variable_set("@#{name}", normalized[name])
      end
    end

    # Build a CardOnFile from a remote response hash, ignoring any unknown or
    # sensitive keys the platform might return.
    def self.from_response(hash)
      new(hash || {})
    end

    # Read-only convenience so expiry/validity is discoverable (edge case, R4).
    # A card is expired when the platform marks its status expired, or when the
    # current date is past the end of its expiry month. Returns false when
    # expiry is unknown — this makes no payment decision (that belongs to `003`).
    def expired?
      return true if status.to_s.downcase == "expired"

      expired_by_date?
    end

    # Serialization is limited to the whitelisted attributes only.
    def to_h
      ATTRIBUTES.each_with_object({}) do |name, acc|
        acc[name] = public_send(name)
      end
    end

    def ==(other)
      other.is_a?(CardOnFile) && other.to_h == to_h
    end
    alias eql? ==

    def hash
      to_h.hash
    end

    def inspect
      pairs = to_h.reject { |_, v| v.nil? }.map { |k, v| "#{k}=#{v.inspect}" }
      "#<BmlTokenization::CardOnFile #{pairs.join(' ')}>"
    end

    private

    # A card is expired when the current date is past the end of its expiry
    # month. Returns false when expiry is unknown — no payment decision is made.
    def expired_by_date?
      return false unless expiry_year && expiry_month

      year = expiry_year.to_i
      month = expiry_month.to_i
      return false if year.zero? || month.zero?

      now = Time.now.utc
      year < now.year || (year == now.year && month < now.month)
    end

    def symbolize(attributes)
      (attributes || {}).each_with_object({}) do |(key, value), acc|
        acc[key.to_sym] = value
      end
    end
  end
end
