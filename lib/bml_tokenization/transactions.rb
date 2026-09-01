# frozen_string_literal: true

module BmlTokenization
  # Transactions resource: create, retrieve, and list payments on the BML
  # platform (FR-001..FR-004).
  #
  # Create supports two completion paths, selected by the presence of a
  # card-on-file safe reference: the redirect path returns a hosted +payment_url+
  # (status +pending+); the stored-card path is charged server-side and resolves
  # directly. Every required input is validated before any remote call (FR-005),
  # amount is a positive integer in MVR minor units and currency is MVR only
  # (FR-005b/c), and create is idempotent on a global integrator reference with a
  # conflict on a reused reference carrying differing parameters (FR-013). Every
  # operation runs against the client's configured environment/credentials
  # (FR-007, FR-008), applies the shared timeout + bounded retry (R2), and maps
  # remote failures to distinguishable errors (FR-009). Create and retrieve emit
  # a card-data-free, payment-URL-free audit record; list is a read and is not
  # audited (FR-012, R11). No full PAN or CVV is ever accepted, returned, or
  # logged (FR-010).
  class Transactions < Resource
    PATH = "/transactions"

    # Required create inputs enforced locally before any remote call (FR-005a).
    REQUIRED_FIELDS = %i[customer_id amount currency reference].freeze

    # The only accepted currency, in minor units (FR-005c, R5).
    CURRENCY = "MVR"

    # Material parameters compared to decide idempotent-replay vs conflict on a
    # reused reference (FR-013).
    MATERIAL_FIELDS = %i[amount currency customer_id card_reference].freeze

    DEFAULT_PAGE_SIZE = 20
    MAX_PAGE_SIZE = 100

    # Initiate a payment for an existing customer (FR-002). Returns a
    # {Transaction}: on the redirect path a +pending+ record carrying a hosted
    # +payment_url+; on the stored-card path a server-side-charged record whose
    # +status+ is resolved directly. Idempotent on the global +reference+: an
    # identical replay returns the existing transaction (no second charge) while
    # a reused reference with differing parameters raises {ConflictError}. Emits
    # a +create+ audit record (no card data, no payment URL — FR-012).
    def create(details, actor: nil)
      attributes = symbolize(details)
      # Accept the audit actor either as a keyword or inside the details hash;
      # it is recorded in the audit "who" and never forwarded to the platform.
      actor ||= attributes[:actor]
      validate_create!(attributes)

      transaction = create_or_existing(attributes)
      Audit.emit_event(client, action: :create, actor: actor, outcome: :success,
                               subject: { transaction_id: transaction.id, reference: transaction.reference })
      log(:create, transaction_id: transaction.id, reference: transaction.reference,
                   customer_id: transaction.customer_id, status: transaction.status, outcome: :success)
      transaction
    end

    # Look up a single transaction by identifier, primarily to learn its status
    # (FR-003, FR-006). Unknown id → {NotFoundError}. Emits a +retrieve+ audit
    # record (FR-012).
    def retrieve(id, actor: nil)
      validate_present!(:id, id)

      response = request(:get, "#{PATH}/#{id}")
      transaction = Transaction.from_response(response)
      Audit.emit_event(client, action: :retrieve, actor: actor, outcome: :success,
                               subject: { transaction_id: transaction.id })
      log(:retrieve, transaction_id: transaction.id, status: transaction.status, outcome: :success)
      transaction
    end

    # Enumerate transactions with page-number pagination (default 20, max 100)
    # and optional, combinable customer/status filters (FR-004). An over-max
    # +page_size+ or an unrecognized +status+ is rejected locally; a page beyond
    # the results (or no matches) yields an empty page, not an error (US3-5). Not
    # audited (read operation, FR-012/R11).
    def list(page: 1, page_size: DEFAULT_PAGE_SIZE, customer_id: nil, status: nil)
      validate_page_size!(page_size)
      validate_status_filter!(status)

      response = request(:get, PATH,
                         params: { page: page, page_size: page_size, customer_id: customer_id, status: status })
      list_page = TransactionList.from_response(response, page: page, page_size: page_size)
      log(:list, outcome: :success, count: list_page.size, page: list_page.page)
      list_page
    end

    private

    # POST the selected create shape, normalizing the platform's duplicate-
    # reference signal (FR-013, R8): a 409 carrying the identical existing record
    # resolves to that record (idempotent replay, no second charge); a 409 whose
    # existing record differs in a material parameter surfaces as a conflict
    # naming the mismatch; a bare conflict (no record) re-raises unchanged.
    def create_or_existing(attributes)
      response = request(:post, PATH, body: build_create_body(attributes))
      Transaction.from_response(response)
    rescue ConflictError => e
      existing = existing_from_conflict(e)
      raise unless existing

      mismatch = material_mismatch(existing, attributes)
      return existing if mismatch.nil?

      raise ConflictError.new(
        "reference #{attributes[:reference].inspect} already used with a different #{mismatch}", body: e.body
      )
    end

    def existing_from_conflict(error)
      body = error.body
      return nil unless body.is_a?(Hash) && !blank?(body["id"] || body["reference"])

      Transaction.from_response(body)
    end

    # The first material parameter that differs between the existing transaction
    # and this request, or nil when they match (an idempotent replay).
    def material_mismatch(existing, attributes)
      MATERIAL_FIELDS.find do |field|
        requested = attributes[field]
        next false if requested.nil?

        existing.public_send(field).to_s != requested.to_s
      end
    end

    # Build the request body for the selected path. The stored-card path sends
    # +card_reference+ (no +return_url+); the redirect path sends +return_url+.
    # Never carries card data or the +actor+ (audit-only) (FR-010).
    def build_create_body(attributes)
      body = {
        "reference" => attributes[:reference],
        "customer_id" => attributes[:customer_id],
        "amount" => attributes[:amount],
        "currency" => CURRENCY
      }
      if redirect_path?(attributes)
        body["return_url"] = attributes[:return_url]
      else
        body["card_reference"] = attributes[:card_reference]
      end
      body
    end

    # Validation order (all pre-remote, no network call on failure — FR-005):
    # presence → amount integer/positive → currency == MVR → return_url required
    # on the redirect path.
    def validate_create!(attributes)
      REQUIRED_FIELDS.each { |field| validate_present!(field, attributes[field]) }
      validate_amount!(attributes[:amount])
      validate_currency!(attributes[:currency])
      validate_return_url!(attributes)
    end

    def validate_amount!(amount)
      return if amount.is_a?(Integer) && amount.positive?

      raise ValidationError.new("amount must be a positive integer in MVR minor units", field: :amount)
    end

    def validate_currency!(currency)
      return if currency == CURRENCY

      raise ValidationError.new("currency must be #{CURRENCY}", field: :currency)
    end

    def validate_return_url!(attributes)
      return unless redirect_path?(attributes)
      return unless blank?(attributes[:return_url])

      raise ValidationError.new("return_url is required for the redirect path", field: :return_url)
    end

    def validate_page_size!(page_size)
      return unless page_size && page_size > MAX_PAGE_SIZE

      raise ValidationError.new("page_size must not exceed #{MAX_PAGE_SIZE}", field: :page_size)
    end

    def validate_status_filter!(status)
      return if blank?(status) || Transaction::STATUSES.include?(status.to_s)

      raise ValidationError.new(
        "status must be one of #{Transaction::STATUSES.join(', ')}", field: :status
      )
    end

    def validate_present!(field, value)
      return unless blank?(value)

      raise ValidationError.new("#{field} is required", field: field)
    end

    # The redirect path is selected when no stored-card reference is supplied.
    def redirect_path?(attributes)
      blank?(attributes[:card_reference])
    end

    def symbolize(input)
      unless input.respond_to?(:each_pair) || input.respond_to?(:to_h)
        raise ValidationError, "transaction details must be provided as a hash"
      end

      (input.to_h || {}).each_with_object({}) do |(key, value), acc|
        acc[key.to_sym] = value
      end
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:strip) && value.strip.empty?)
    end

    # Emit a structured, masked log line. No-op when no logger is configured. The
    # hosted payment URL and any card data are never passed here (FR-010, R11).
    def log(operation, fields)
      logger = client.logger
      return unless logger

      entry = Masking.scrub({ operation: operation, resource: "transactions" }.merge(fields))
      logger.info(entry)
    end
  end
end
