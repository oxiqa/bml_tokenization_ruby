# frozen_string_literal: true

module BmlTokenization
  # A customer's cards on file returned for a single list request (FR-004, R11).
  #
  # The set is small and bounded — a wallet, not an unbounded collection — so
  # there is no pagination. A customer with no stored cards yields an empty
  # +records+ set, which is valid and not an error (US2-2). Each element is a
  # {CardOnFile} exposing only a safe reference + masked summary.
  class CardOnFileList
    include Enumerable

    attr_reader :customer_id, :records

    def initialize(customer_id:, records:)
      @customer_id = customer_id
      @records = records
    end

    # Build a list from a remote response and the requested customer id. An
    # empty (or absent) +data+ array yields an empty list, not an error.
    def self.from_response(hash, customer_id: nil)
      hash ||= {}
      raw = hash["data"] || hash["records"] || []
      new(
        customer_id: hash["customer_id"] || customer_id,
        records: raw.map { |record| CardOnFile.from_response(record) }
      )
    end

    def each(&block)
      records.each(&block)
    end

    def empty?
      records.empty?
    end

    def size
      records.size
    end
  end
end
