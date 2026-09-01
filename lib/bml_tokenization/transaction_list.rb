# frozen_string_literal: true

module BmlTokenization
  # A bounded page of transactions from a single list request, plus the metadata
  # to request further pages (data-model.md, FR-004, R7).
  #
  # Requesting a page beyond the available results, or listing when none match
  # the filters, yields an empty page (empty +records+) rather than an error
  # (US3-5).
  class TransactionList
    include Enumerable

    attr_reader :records, :page, :page_size, :total_count

    def initialize(records:, page:, page_size:, total_count: nil)
      @records = records
      @page = page
      @page_size = page_size
      @total_count = total_count
    end

    # Build a page from a remote list response and the echoed pagination inputs.
    # Accepts either a +records+ or +data+ array from the platform.
    def self.from_response(hash, page:, page_size:)
      hash ||= {}
      raw = hash["records"] || hash["data"] || []

      new(
        records: raw.map { |record| Transaction.from_response(record) },
        page: hash.fetch("page", page),
        page_size: hash.fetch("page_size", page_size),
        total_count: hash["total_count"]
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
