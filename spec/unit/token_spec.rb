# frozen_string_literal: true

# Unit spec for the Token value object (data-model.md Token). A Token is exposed
# only as a platform-assigned safe +reference+ plus a masked summary (scheme,
# last4, expiry) and a validity +status+. No accessor, serialization, or
# inspect/to_s ever reveals a full PAN/CVV (FR-003, FR-006a, R7).
RSpec.describe BmlTokenization::Token do
  let(:token_json) do
    {
      "token_reference" => "tok_ref_1", "scheme" => "visa", "last4" => "4242",
      "expiry_month" => 12, "expiry_year" => 2030, "status" => "active"
    }
  end

  describe ".from_response" do
    it "maps the remote token_reference to the safe reference and exposes only masked fields" do
      token = described_class.from_response(token_json)

      expect(token.reference).to eq("tok_ref_1")
      expect(token.scheme).to eq("visa")
      expect(token.last4).to eq("4242")
      expect(token.expiry_month).to eq(12)
      expect(token.expiry_year).to eq(2030)
      expect(token.status).to eq("active")
    end

    it "also accepts a plain reference key" do
      token = described_class.from_response(token_json.merge("token_reference" => nil, "reference" => "tok_ref_2"))

      expect(token.reference).to eq("tok_ref_2")
    end

    it "carries the optional environment when supplied (informational, from client config)" do
      token = described_class.from_response(token_json, environment: :sandbox)

      expect(token.environment).to eq(:sandbox)
    end
  end

  describe "no full PAN/CVV exposure (FR-003, FR-006a)" do
    let(:leaky) do
      token_json.merge("card_number" => "4111111111111111", "pan" => "4111111111111111",
                       "cvv" => "123", "card_handle" => "handle_secret")
    end

    it "drops any full PAN/CVV/handle the platform leaks back — only whitelisted fields survive" do
      token = described_class.from_response(leaky)

      dump = token.to_h.to_s + token.inspect + token.to_s
      expect(dump).not_to include("4111111111111111")
      expect(dump).not_to include("123123")
      expect(dump).not_to include("handle_secret")
      expect(dump).not_to match(/\b(?:\d[ -]?){12,19}\b/)
    end

    it "exposes no accessor that returns a full card number" do
      token = described_class.from_response(leaky)

      expect(token).not_to respond_to(:card_number)
      expect(token).not_to respond_to(:pan)
      expect(token).not_to respond_to(:cvv)
    end

    it "serializes (to_h) only the whitelisted masked attributes" do
      token = described_class.from_response(leaky)

      expect(token.to_h.keys).to match_array(described_class::ATTRIBUTES)
    end
  end

  describe "validity status helpers (FR-004)" do
    it "reports active/revoked/expired distinctly" do
      expect(described_class.from_response(token_json.merge("status" => "active")).active?).to be(true)
      expect(described_class.from_response(token_json.merge("status" => "revoked")).revoked?).to be(true)
      expect(described_class.from_response(token_json.merge("status" => "expired")).expired?).to be(true)
    end

    it "is not active once revoked or expired" do
      expect(described_class.from_response(token_json.merge("status" => "revoked")).active?).to be(false)
      expect(described_class.from_response(token_json.merge("status" => "expired")).active?).to be(false)
    end
  end

  describe "value semantics" do
    it "is equal to another Token with the same attributes" do
      expect(described_class.from_response(token_json)).to eq(described_class.from_response(token_json))
    end
  end
end
