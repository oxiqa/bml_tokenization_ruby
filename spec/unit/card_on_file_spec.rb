# frozen_string_literal: true

# Unit spec for the CardOnFile value object (data-model.md, FR-003): exposes the
# safe reference + masked summary and a derived expired?, and NEVER a full PAN,
# CVV, single-use handle, or any SAD attribute.
RSpec.describe BmlTokenization::CardOnFile do
  let(:attributes) do
    {
      "reference" => "card_ref_1",
      "customer_id" => "cust_1",
      "scheme" => "visa",
      "last_four" => "4242",
      "expiry_month" => 12,
      "expiry_year" => 2030,
      "status" => "active",
      "created_at" => "2026-08-27T00:00:00Z"
    }
  end

  subject(:card) { described_class.from_response(attributes) }

  it "exposes the safe reference + masked summary fields" do
    expect(card.reference).to eq("card_ref_1")
    expect(card.customer_id).to eq("cust_1")
    expect(card.scheme).to eq("visa")
    expect(card.last_four).to eq("4242")
    expect(card.expiry_month).to eq(12)
    expect(card.expiry_year).to eq(2030)
    expect(card.status).to eq("active")
    expect(card.created_at).to eq("2026-08-27T00:00:00Z")
  end

  describe "#expired?" do
    it "is false for a future expiry" do
      expect(described_class.new(expiry_month: 12, expiry_year: 2999).expired?).to be(false)
    end

    it "is true for a past expiry" do
      expect(described_class.new(expiry_month: 1, expiry_year: 2000).expired?).to be(true)
    end

    it "is true when the platform status says expired" do
      expect(described_class.new(status: "expired").expired?).to be(true)
    end

    it "is false (no payment decision) when expiry is unknown" do
      expect(described_class.new(reference: "r").expired?).to be(false)
    end
  end

  describe "no SAD/PAN exposure (FR-003, data-model forbidden fields)" do
    it "has no accessor for a full PAN, CVV, single-use handle, or SAD" do
      %i[pan card_number cardnumber number cvv cvv2 cvc pin track track1 track2 card_handle handle].each do |forbidden|
        expect(card).not_to respond_to(forbidden)
      end
    end

    it "drops any forbidden field the platform returns — never retained or serialized" do
      leaky = described_class.from_response(
        attributes.merge("card_number" => "4111111111111111", "cvv" => "123", "card_handle" => "tok_secret")
      )

      expect(leaky).not_to respond_to(:card_number)
      serialized = leaky.to_h.to_s + leaky.inspect
      expect(serialized).not_to include("4111111111111111")
      expect(serialized).not_to include("tok_secret")
      expect(serialized).not_to include("123") # cvv
    end

    it "serializes exactly the whitelisted attributes" do
      expect(card.to_h.keys).to contain_exactly(
        :reference, :customer_id, :scheme, :last_four, :expiry_month, :expiry_year, :status, :created_at
      )
    end
  end

  it "supports value equality" do
    expect(described_class.from_response(attributes)).to eq(described_class.from_response(attributes))
  end
end
