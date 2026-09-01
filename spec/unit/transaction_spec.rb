# frozen_string_literal: true

# Unit spec for the Transaction value object (data-model.md, FR-006, FR-010, R6):
# the four normalized statuses; payment_url present only on the redirect path and
# card_reference only on the stored-card path; and no full PAN/CVV field anywhere,
# by whitelist construction.
RSpec.describe BmlTokenization::Transaction do
  let(:redirect_json) do
    { "id" => "txn_1", "reference" => "order-1", "customer_id" => "cus_1", "amount" => 15_000,
      "currency" => "MVR", "status" => "pending",
      "payment_url" => "https://connect.bml.example/pay/txn_1", "created_at" => "2026-08-27T10:00:00Z" }
  end
  let(:stored_card_json) do
    { "id" => "txn_2", "reference" => "order-2", "customer_id" => "cus_1", "amount" => 15_000,
      "currency" => "MVR", "status" => "succeeded", "card_reference" => "cof_safe_abc" }
  end

  describe "the four normalized statuses (FR-006, R6)" do
    %w[pending succeeded failed cancelled].each do |canonical|
      it "passes through the canonical status #{canonical.inspect}" do
        expect(described_class.new(status: canonical).status).to eq(canonical)
      end
    end

    it "normalizes case and common platform synonyms to the canonical value" do
      expect(described_class.new(status: "PENDING").status).to eq("pending")
      expect(described_class.new(status: "success").status).to eq("succeeded")
      expect(described_class.new(status: "canceled").status).to eq("cancelled")
      expect(described_class.new(status: "declined").status).to eq("failed")
    end

    it "leaves status nil when the platform returned none" do
      expect(described_class.new({}).status).to be_nil
    end
  end

  describe "completion route is characterized by exactly one of payment_url / card_reference (R3)" do
    it "exposes payment_url (and no card_reference) on the redirect path" do
      txn = described_class.from_response(redirect_json)

      expect(txn.payment_url).to eq("https://connect.bml.example/pay/txn_1")
      expect(txn.card_reference).to be_nil
      expect(txn.status).to eq("pending")
    end

    it "exposes card_reference (and no payment_url) on the stored-card path" do
      txn = described_class.from_response(stored_card_json)

      expect(txn.card_reference).to eq("cof_safe_abc")
      expect(txn.payment_url).to be_nil
      expect(txn.status).to eq("succeeded")
    end
  end

  describe "no PAN/CVV/SAD field exists, by construction (FR-010, SC-005)" do
    it "drops any card data the platform leaks back and never exposes it" do
      leaky = redirect_json.merge("card_number" => "4111111111111111", "cvv" => "123", "pan" => "4111111111111111")

      txn = described_class.from_response(leaky)

      %i[card_number cvv pan cvv2 track track2 pin].each do |forbidden|
        expect(txn).not_to respond_to(forbidden)
      end
      serialized = txn.to_h.to_s + txn.inspect
      expect(serialized).not_to include("4111111111111111")
      expect(serialized).not_to include("123")
      expect(serialized).not_to match(/\b(?:\d[ -]?){12,19}\b/)
    end
  end

  it "carries the platform id, reference, customer, amount, and currency" do
    txn = described_class.from_response(redirect_json)

    expect(txn.id).to eq("txn_1")
    expect(txn.reference).to eq("order-1")
    expect(txn.customer_id).to eq("cus_1")
    expect(txn.amount).to eq(15_000)
    expect(txn.currency).to eq("MVR")
    expect(txn.created_at).to eq("2026-08-27T10:00:00Z")
  end

  it "serializes only the whitelisted attributes and compares by value" do
    a = described_class.from_response(redirect_json)
    b = described_class.from_response(redirect_json)

    expect(a).to eq(b)
    expect(a.to_h.keys).to contain_exactly(
      :id, :reference, :customer_id, :amount, :currency, :status,
      :payment_url, :card_reference, :return_url, :created_at
    )
  end
end
