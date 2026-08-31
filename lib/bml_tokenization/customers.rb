# frozen_string_literal: true

module BmlTokenization
  # Customers resource: create, retrieve, list (paginated), and update customer
  # records on the BML platform (FR-001..FR-005).
  #
  # Every operation validates required inputs before any remote call (FR-006),
  # runs against the client's configured environment/credentials (FR-007,
  # FR-008), maps remote failures to distinguishable errors (FR-009), and emits
  # only masked, structured log lines carrying no card data or SAD (FR-010).
  class Customers < Resource
    PATH = "/customers"

    # Locally-enforced required fields (R3). The platform enforces the rest.
    REQUIRED_FIELDS = %i[first_name last_name email].freeze

    # The mutable fields forwarded to the platform on create/update.
    WRITABLE_FIELDS = %i[first_name last_name email phone reference].freeze

    DEFAULT_PAGE_SIZE = 20
    MAX_PAGE_SIZE = 100

    # Register a new customer. Returns a {Customer} with the platform-assigned
    # +id+ plus the submitted details (FR-002).
    def create(details)
      attributes = symbolize(details)
      validate_required!(attributes)

      response = request(:post, PATH, body: build_body(attributes))
      customer = Customer.from_response(response)
      log(:create, customer_id: customer.id, outcome: :success)
      customer
    end

    # Look up a single customer by identifier (FR-003). Unknown id → not-found.
    def retrieve(id)
      validate_id!(id)

      response = request(:get, "#{PATH}/#{id}")
      customer = Customer.from_response(response)
      log(:retrieve, customer_id: customer.id, outcome: :success)
      customer
    end

    # Browse customers with page-number pagination (FR-004). +page_size+
    # defaults to 20 and must not exceed 100 (over-cap rejected pre-remote).
    def list(page: 1, page_size: DEFAULT_PAGE_SIZE)
      validate_page_size!(page_size)

      response = request(:get, PATH, params: { page: page, page_size: page_size })
      list_page = CustomerListPage.from_response(response, page: page, page_size: page_size)
      log(:list, outcome: :success, count: list_page.size, page: list_page.page)
      list_page
    end

    # Replace a customer's mutable details using full-replace semantics (FR-005,
    # R9): the complete record is required and any omitted mutable field is
    # cleared on the platform. Same required-field validation as create.
    def update(id, record)
      validate_id!(id)
      attributes = symbolize(record)
      validate_required!(attributes)

      response = request(:put, "#{PATH}/#{id}", body: build_body(attributes))
      customer = Customer.from_response(response)
      log(:update, customer_id: customer.id, outcome: :success)
      customer
    end

    private

    def validate_required!(attributes)
      REQUIRED_FIELDS.each do |field|
        value = attributes[field]
        next unless blank?(value)

        raise ValidationError.new("#{field} is required", field: field)
      end
    end

    def validate_id!(id)
      return unless blank?(id)

      raise ValidationError.new("id is required", field: :id)
    end

    def validate_page_size!(page_size)
      return unless page_size && page_size > MAX_PAGE_SIZE

      raise ValidationError.new(
        "page_size must not exceed #{MAX_PAGE_SIZE}", field: :page_size
      )
    end

    # Build the request body from the writable fields only. Full-replace: every
    # writable field is sent (optional ones as null when omitted) so the
    # platform clears anything left out (R9). Never carries card data (FR-010).
    def build_body(attributes)
      WRITABLE_FIELDS.each_with_object({}) do |field, body|
        body[field.to_s] = attributes[field]
      end
    end

    def symbolize(input)
      unless input.respond_to?(:each_pair) || input.respond_to?(:to_h)
        raise ValidationError, "customer details must be provided as a hash"
      end

      (input.to_h || {}).each_with_object({}) do |(key, value), acc|
        acc[key.to_sym] = value
      end
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:strip) && value.strip.empty?)
    end

    # Emit a structured, masked log line. No-op when no logger is configured.
    def log(operation, fields)
      logger = client.logger
      return unless logger

      entry = Masking.scrub({ operation: operation, resource: "customers" }.merge(fields))
      logger.info(entry)
    end
  end
end
