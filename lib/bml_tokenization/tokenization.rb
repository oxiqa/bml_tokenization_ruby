# frozen_string_literal: true

module BmlTokenization
  # Tokenization resource: tokenize a captured card, retrieve a token's masked
  # details, and revoke a token (FR-001..FR-006).
  #
  # The only card input accepted is a single-use hosted-capture handle (FR-002);
  # a raw PAN or CVV is never accepted, returned, or logged (FR-003), and no
  # operation ever reveals a full card number — there is deliberately no
  # detokenize path (FR-006a). Every operation validates its inputs before any
  # remote call (FR-007), runs against the client's configured environment and
  # credentials (FR-008, FR-009), applies the shared timeout + bounded retry
  # (FR-014), and maps remote failures to distinguishable errors (FR-010).
  #
  # Tokenize is idempotent per account + environment: the same underlying card
  # yields the existing token, never a duplicate (FR-011). Revoke permanently
  # invalidates a token (terminal +revoked+) and performs NO cascade — it issues
  # no call that deletes or mutates card-on-file or transaction records that
  # reference the token (FR-005, FR-005a); those references simply become
  # unusable. Every operation emits a card-data-free audit record (FR-012,
  # FR-012a).
  class Tokenization < Resource
    PATH = "/tokens"

    # Issue a token for a captured card from a single-use handle (FR-002). Returns
    # a {Token} (status +active+) with a safe, non-reversible reference + masked
    # summary — never a full PAN/CVV (FR-003, FR-006). Re-tokenizing the same card
    # within this account + environment returns the existing token (idempotent, no
    # duplicate — FR-011). Emits a +tokenize+ audit record (FR-012).
    def tokenize(card_handle, actor: nil)
      validate_present!(:card_handle, card_handle)
      validate_actor!(actor)

      token = tokenize_or_existing(card_handle)
      audit(:tokenize, token.reference, actor)
      log(:tokenize, token_reference: token.reference, status: token.status, outcome: :success)
      token
    end

    # Look up a token's current masked details and validity status (FR-004).
    # Returns a {Token} with the masked summary + +status+ only; no full PAN/CVV
    # (FR-003). Unknown reference → {NotFoundError} (US2-2). Emits a +retrieve+
    # audit record (FR-012).
    def retrieve(reference, actor: nil)
      validate_present!(:reference, reference)

      response = request(:get, "#{PATH}/#{reference}")
      token = build_token(response)
      audit(:retrieve, reference, actor)
      log(:retrieve, token_reference: reference, status: token.status, outcome: :success)
      token
    end

    # Permanently invalidate a token (FR-005). Terminal: the token becomes
    # +revoked+ and is never reactivated. Performs NO cascade — no call that
    # deletes or mutates any card-on-file or transaction record referencing the
    # token (FR-005a); later use of the token is rejected by the consuming
    # operation. Unknown reference → {NotFoundError}; an already-revoked token →
    # {ConflictError} (US3-2). Emits a +revoke+ audit record (FR-012).
    def revoke(reference, actor: nil)
      validate_present!(:reference, reference)

      # A single call to the token's own revoke endpoint — nothing else is
      # touched, which is what guarantees no cascade (FR-005a).
      response = request(:post, "#{PATH}/#{reference}/revoke")
      token = build_token(response)
      audit(:revoke, reference, actor)
      log(:revoke, token_reference: reference, status: token.status, outcome: :success)
      token
    end

    private

    # POST the handle, normalizing an already-tokenized outcome to an idempotent
    # success. The platform is the source of truth for sameness (R4): a 2xx with
    # the existing token, or a 409 carrying the existing token reference, both
    # return the existing {Token} — no duplicate, no error surfaced (FR-011). A
    # genuine conflict (no reference) re-raises.
    def tokenize_or_existing(card_handle)
      response = request(:post, PATH, body: { "card_handle" => card_handle })
      build_token(response)
    rescue ConflictError => e
      existing = existing_from_conflict(e)
      raise unless existing

      existing
    end

    def existing_from_conflict(error)
      body = error.body
      return nil unless body.is_a?(Hash)
      return nil if blank?(body["token_reference"] || body["reference"])

      build_token(body)
    end

    # Build a {Token}, tagging it with the client's configured environment so a
    # token always reports the environment it belongs to (FR-008).
    def build_token(response)
      Token.from_response(response, environment: client.environment)
    end

    def validate_present!(field, value)
      return unless blank?(value)

      raise ValidationError.new("#{field} is required", field: field)
    end

    # The optional audit actor must never carry cardholder data: reject anything
    # that looks like a PAN before it can reach the audit record (FR-012a,
    # data-model Actor Reference).
    def validate_actor!(actor)
      return if actor.nil?
      return unless actor.to_s.match?(Masking::PAN_PATTERN)

      raise ValidationError.new("actor must not contain a card number", field: :actor)
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:strip) && value.strip.empty?)
    end

    # Emit one card-data-free audit record for the operation. The subject is the
    # safe token reference only — never the handle, PAN, or CVV (FR-012, FR-012a).
    def audit(action, token_reference, actor)
      Audit.emit_event(client, action: action, actor: actor, outcome: :success,
                               subject: { token_reference: token_reference })
    end

    # Emit a structured, masked log line. No-op when no logger is configured. The
    # single-use handle, PAN, and CVV are never passed here (FR-003, FR-013).
    def log(operation, fields)
      logger = client.logger
      return unless logger

      entry = Masking.scrub({ operation: operation, resource: "tokenization" }.merge(fields))
      logger.info(entry)
    end
  end
end
