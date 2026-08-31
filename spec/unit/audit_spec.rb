# frozen_string_literal: true

# Unit spec for the shared audit concern (FR-006a, FR-015, research R10): a
# state-change audit record captures action / card_reference / actor (client
# identity + optional integrator actor) / occurred_at / outcome, dispatches to
# the configured sink, and contains NO card data beyond the safe reference.
RSpec.describe BmlTokenization::Audit do
  let(:sink) { [] }
  let(:client) do
    BmlTokenization::Client.new(api_key: "key", app_id: "app-123", environment: :sandbox, audit_sink: sink)
  end

  describe ".build" do
    it "captures action, card_reference, actor, occurred_at, and outcome" do
      record = described_class.build(client, action: :store, card_reference: "card_ref_1", outcome: :success)

      expect(record.action).to eq("store")
      expect(record.card_reference).to eq("card_ref_1")
      expect(record.outcome).to eq("success")
      expect(record.occurred_at).to be_a(Time)
      expect(record.to_h.keys).to contain_exactly(:action, :card_reference, :actor, :occurred_at, :outcome)
    end

    it "records who = client identity, plus the optional integrator actor when provided" do
      without_actor = described_class.build(client, action: :remove, card_reference: "r", outcome: :success)
      with_actor = described_class.build(client, action: :remove, card_reference: "r", outcome: :success,
                                                 actor: "user-42")

      expect(without_actor.actor).to eq("app-123")
      expect(with_actor.actor).to include("app-123").and include("user-42")
    end

    it "contains NO card data beyond the safe reference" do
      record = described_class.build(client, action: :store, card_reference: "safe_ref", outcome: :success)

      serialized = record.to_h.to_s
      expect(serialized).not_to match(/\b(?:\d[ -]?){12,19}\b/) # no PAN-shaped value
      %i[pan card_number cvv card_handle last_four scheme].each do |forbidden|
        expect(record).not_to respond_to(forbidden)
      end
    end
  end

  describe ".emit" do
    it "dispatches the built record to the client's audit sink" do
      record = described_class.emit(client, action: :store, card_reference: "ref_9", outcome: :success)

      expect(sink).to eq([record])
      expect(sink.first.card_reference).to eq("ref_9")
    end

    it "supports a callable sink" do
      captured = nil
      callable_client = BmlTokenization::Client.new(
        app_id: "app-x", audit_sink: ->(rec) { captured = rec }
      )

      described_class.emit(callable_client, action: :remove, card_reference: "r2", outcome: :success)

      expect(captured.action).to eq("remove")
    end

    it "is a no-op (still returns the record) when no sink is configured" do
      no_sink = BmlTokenization::Client.new(app_id: "app-y")

      record = described_class.emit(no_sink, action: :store, card_reference: "r3", outcome: :success)

      expect(record).to be_a(BmlTokenization::AuditRecord)
    end
  end
end
