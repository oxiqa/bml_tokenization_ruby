# frozen_string_literal: true

require "time"

module BmlTokenization
  # An immutable audit record emitted for a state-changing operation (store,
  # remove). It captures who / what / when / outcome and — by construction —
  # carries no card data beyond the safe reference (FR-006a, FR-015, R10).
  #
  # Only the five fields below exist on the record; there is no slot for a PAN,
  # CVV, the single-use handle, or the masked summary.
  class AuditRecord
    ATTRIBUTES = %i[action card_reference actor occurred_at outcome].freeze

    attr_reader(*ATTRIBUTES)

    def initialize(action:, card_reference:, actor:, occurred_at:, outcome:)
      @action = action
      @card_reference = card_reference
      @actor = actor
      @occurred_at = occurred_at
      @outcome = outcome
    end

    def to_h
      ATTRIBUTES.each_with_object({}) do |name, acc|
        acc[name] = public_send(name)
      end
    end

    def ==(other)
      other.is_a?(AuditRecord) && other.to_h == to_h
    end
    alias eql? ==

    def hash
      to_h.hash
    end
  end

  # Shared audit concern: builds and dispatches an {AuditRecord} for a
  # state-changing action. Reads (list, retrieve) never call this (FR-015).
  #
  # "Who" is the configured client/API identity (the App ID) plus an optional
  # integrator-supplied actor reference. The record is dispatched to the
  # client's +audit_sink+ (a callable or an appendable) when one is configured.
  module Audit
    module_function

    # Build and dispatch an audit record, returning it.
    def emit(client, action:, card_reference:, outcome:, actor: nil)
      record = build(client, action: action, card_reference: card_reference, outcome: outcome, actor: actor)
      dispatch(client, record)
      record
    end

    # Build an audit record without dispatching (used in tests and by {emit}).
    def build(client, action:, card_reference:, outcome:, actor: nil)
      AuditRecord.new(
        action: action.to_s,
        card_reference: card_reference,
        actor: actor_identity(client, actor),
        occurred_at: Time.now.utc,
        outcome: outcome.to_s
      )
    end

    # "Who": the client/API identity plus the optional integrator actor.
    def actor_identity(client, actor)
      identity = client.respond_to?(:app_id) && client.app_id ? client.app_id : "client"
      actor ? "#{identity}:#{actor}" : identity
    end

    def dispatch(client, record)
      sink = client.respond_to?(:audit_sink) ? client.audit_sink : nil
      return unless sink

      if sink.respond_to?(:call)
        sink.call(record)
      elsif sink.respond_to?(:<<)
        sink << record
      end
    end
  end
end
