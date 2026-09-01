# frozen_string_literal: true

require "time"

module BmlTokenization
  # An immutable audit record emitted for a state-changing operation. It captures
  # who / what / when / outcome and — by construction — carries only the safe
  # identifiers handed to it: never a PAN, CVV, single-use handle, or a hosted
  # payment URL (FR-006a, FR-012, FR-015, R10/R11).
  #
  # The record is built from an ordered attribute hash (the "subject" identifiers
  # sit between the action and the actor). Only those attributes are exposed —
  # anything not supplied is not a method on the record, so a caller cannot read
  # card data off it and a serialization cannot leak it.
  class AuditRecord
    def initialize(attributes)
      @attributes = attributes.dup
      @attributes.each_key do |name|
        define_singleton_method(name) { @attributes[name] }
      end
    end

    def to_h
      @attributes.dup
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
  # state-changing action. Reads that are out of FR-012/FR-015 scope (card list,
  # card retrieve; transaction list) never call this.
  #
  # "Who" is the configured client/API identity (the App ID) plus an optional
  # integrator-supplied actor reference. The record is dispatched to the client's
  # +audit_sink+ (a callable or an appendable) when one is configured.
  module Audit
    module_function

    # Build and dispatch a card state-change record (002), returning it. The
    # subject is the card's safe reference — never any card data.
    def emit(client, action:, card_reference:, outcome:, actor: nil)
      record = build(client, action: action, card_reference: card_reference, outcome: outcome, actor: actor)
      dispatch(client, record)
      record
    end

    # Build a card state-change record without dispatching (used in tests and by
    # {emit}).
    def build(client, action:, card_reference:, outcome:, actor: nil)
      record_for(client, action: action, outcome: outcome, actor: actor,
                         subject: { card_reference: card_reference })
    end

    # Build and dispatch a generic event record (003 transactions and future
    # resources), returning it. +subject+ is a hash of SAFE identifiers only
    # (e.g. transaction_id / reference) — never card data or a payment URL
    # (FR-012, R11).
    def emit_event(client, action:, outcome:, subject: {}, actor: nil)
      record = build_event(client, action: action, outcome: outcome, subject: subject, actor: actor)
      dispatch(client, record)
      record
    end

    # Build a generic event record without dispatching (used in tests and by
    # {emit_event}).
    def build_event(client, action:, outcome:, subject: {}, actor: nil)
      record_for(client, action: action, outcome: outcome, actor: actor, subject: subject)
    end

    # Assemble the ordered attribute hash and wrap it in an {AuditRecord}:
    # action, then the safe subject identifiers, then who / when / outcome.
    def record_for(client, action:, outcome:, actor:, subject:)
      attributes = { action: action.to_s }
      subject.each { |name, value| attributes[name] = value }
      attributes[:actor] = actor_identity(client, actor)
      attributes[:occurred_at] = Time.now.utc
      attributes[:outcome] = outcome.to_s
      AuditRecord.new(attributes)
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
