# frozen_string_literal: true

module BmlTokenization
  # Immutable customer record returned by create, retrieve, list, and update.
  #
  # Only the whitelisted customer-contact attributes below are ever exposed.
  # Any card data or Sensitive Authentication Data present in a response is
  # silently discarded and can never appear on the object or its serialization
  # (FR-010, data-model.md).
  class Customer
    # The complete, exhaustive attribute set. No SAD/PAN attribute exists here,
    # by construction — nothing outside this list is retained.
    ATTRIBUTES = %i[
      id first_name last_name email phone reference created_at updated_at
    ].freeze

    attr_reader(*ATTRIBUTES)

    def initialize(attributes = {})
      normalized = symbolize(attributes)
      ATTRIBUTES.each do |name|
        instance_variable_set("@#{name}", normalized[name])
      end
    end

    # Build a Customer from a remote response hash, ignoring any unknown or
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
      other.is_a?(Customer) && other.to_h == to_h
    end
    alias eql? ==

    def hash
      to_h.hash
    end

    def inspect
      pairs = to_h.reject { |_, v| v.nil? }.map { |k, v| "#{k}=#{v.inspect}" }
      "#<BmlTokenization::Customer #{pairs.join(' ')}>"
    end

    private

    def symbolize(attributes)
      (attributes || {}).each_with_object({}) do |(key, value), acc|
        acc[key.to_sym] = value
      end
    end
  end
end
