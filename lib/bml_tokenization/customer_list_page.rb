# frozen_string_literal: true

module BmlTokenization
  # A bounded page of customer records from a single list request, plus the
  # information needed to request subsequent pages (FR-004, R4).
  #
  # Requesting a page beyond the available results, or listing when none exist,
  # yields an empty page (empty +records+) rather than an error.
  class CustomerListPage
    attr_reader :records, :page, :page_size

    def initialize(records:, page:, page_size:, has_next: false, next_page: nil)
      @records = records
      @page = page
      @page_size = page_size
      @has_next = has_next
      @next_page = next_page
    end

    # Build a page from a remote list response and the echoed pagination inputs.
    def self.from_response(hash, page:, page_size:)
      hash ||= {}
      raw_records = hash["data"] || hash["records"] || []
      records = raw_records.map { |record| Customer.from_response(record) }

      new(
        records: records,
        page: hash.fetch("page", page),
        page_size: hash.fetch("page_size", page_size),
        has_next: hash.fetch("has_next", false),
        next_page: hash["next_page"]
      )
    end

    # Whether a further page exists after this one.
    def has_next?
      @has_next ? true : false
    end
    alias has_next has_next?

    # The next page number to request, or nil on the final page.
    def next_page
      return @next_page unless @next_page.nil?

      has_next? ? page + 1 : nil
    end

    def empty?
      records.empty?
    end

    def size
      records.size
    end

    def each(&block)
      records.each(&block)
    end
    include Enumerable
  end
end
