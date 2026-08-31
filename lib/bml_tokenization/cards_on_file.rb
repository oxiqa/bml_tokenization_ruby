# frozen_string_literal: true

module BmlTokenization
  # CardsOnFile resource: store, list, retrieve, and remove a customer's saved
  # payment cards on the BML platform (FR-001..FR-006).
  #
  # The only card input accepted is a pre-tokenized, single-use card handle
  # (FR-002); a raw PAN or CVV is never accepted, returned, or logged (FR-003).
  # Every operation validates required inputs before any remote call (FR-007),
  # runs against the client's configured environment/credentials (FR-008,
  # FR-009), applies the shared timeout + bounded retry (FR-014), and maps
  # remote failures to distinguishable errors (FR-010). Storing an already
  # on-file card is idempotent (FR-013); removal is permanent (FR-006). The
  # state-changing operations (store, remove) emit a card-data-free audit
  # record; reads (list, retrieve) do not (FR-006a, FR-015).
  class CardsOnFile < Resource
    PATH = "/cards-on-file"

    # Save a customer's card for reuse from a single-use handle (FR-002). Returns
    # a {CardOnFile} with a safe reference + masked summary — never a full card
    # number. Re-storing a card already on file returns the existing record
    # (idempotent, no duplicate — FR-013). Emits a +store+ audit record.
    def store(customer_id:, card_handle:, actor: nil)
      validate_present!(:customer_id, customer_id)
      validate_present!(:card_handle, card_handle)

      card = store_or_existing(customer_id, card_handle)
      Audit.emit(client, action: :store, card_reference: card.reference, actor: actor, outcome: :success)
      log(:store, card_reference: card.reference, customer_id: customer_id, outcome: :success)
      card
    end

    # Enumerate all of a customer's cards on file (FR-004). No pagination. A
    # customer with no cards yields an empty {CardOnFileList}, not an error
    # (US2-2). Not audited (read operation, FR-015).
    def list(customer_id:)
      validate_present!(:customer_id, customer_id)

      response = request(:get, PATH, params: { customer_id: customer_id })
      list = CardOnFileList.from_response(response, customer_id: customer_id)
      log(:list, customer_id: customer_id, outcome: :success, count: list.size)
      list
    end

    # Look up a single card on file by its safe reference (FR-005). Unknown
    # reference → not-found (US3-2). Not audited (read operation, FR-015).
    def retrieve(reference)
      validate_present!(:reference, reference)

      response = request(:get, "#{PATH}/#{reference}")
      card = CardOnFile.from_response(response)
      log(:retrieve, card_reference: reference, outcome: :success)
      card
    end

    # Permanently delete a saved card (FR-006). Afterward it is absent from the
    # customer's list and retrieval returns not-found; it is not recoverable.
    # An unknown/already-removed reference → not-found, no other card affected
    # (US4-2). Emits a +remove+ audit record with no card data (FR-006a).
    def remove(reference, actor: nil)
      validate_present!(:reference, reference)

      request(:delete, "#{PATH}/#{reference}")
      Audit.emit(client, action: :remove, card_reference: reference, actor: actor, outcome: :success)
      log(:remove, card_reference: reference, outcome: :success)
      true
    end

    private

    # POST the handle + customer association, normalising an already-on-file
    # outcome to an idempotent success. The platform is the source of truth for
    # sameness (R5): a 2xx with the existing record, or a 409 carrying the
    # existing reference, both return the existing {CardOnFile} — no duplicate,
    # no error surfaced (FR-013). A genuine conflict (no reference) re-raises.
    def store_or_existing(customer_id, card_handle)
      response = request(:post, PATH, body: { "customer_id" => customer_id, "card_handle" => card_handle })
      CardOnFile.from_response(response)
    rescue ConflictError => e
      existing = existing_from_conflict(e)
      raise unless existing

      existing
    end

    def existing_from_conflict(error)
      body = error.body
      return nil unless body.is_a?(Hash) && !blank?(body["reference"])

      CardOnFile.from_response(body)
    end

    def validate_present!(field, value)
      return unless blank?(value)

      raise ValidationError.new("#{field} is required", field: field)
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:strip) && value.strip.empty?)
    end

    # Emit a structured, masked log line. No-op when no logger is configured.
    # The single-use handle, PAN, and CVV are never passed here (FR-003, R12).
    def log(operation, fields)
      logger = client.logger
      return unless logger

      entry = Masking.scrub({ operation: operation, resource: "cards_on_file" }.merge(fields))
      logger.info(entry)
    end
  end
end
