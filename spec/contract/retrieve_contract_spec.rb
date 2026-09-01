# frozen_string_literal: true

# Verifies the public library API + BML remote HTTP contract for retrieve
# (contracts/*): the get-token request carries auth headers; the response maps
# to a masked-only Token with a validity status; unknown reference → not-found;
# a retrieve audit record is emitted.
RSpec.describe "Tokenization#retrieve contract" do
  let(:base) { BmlTokenization::Client::BASE_URLS[:sandbox] }
  let(:audit_sink) { [] }
  let(:client) do
    BmlTokenization::Client.new(
      api_key: "key", app_id: "app", environment: :sandbox, retry_backoff: 0, audit_sink: audit_sink
    )
  end
  let(:tokens) { client.tokenization }
  let(:token_json) do
    { token_reference: "tok_ref_1", scheme: "visa", last4: "4242",
      expiry_month: 12, expiry_year: 2028, status: "active" }
  end

  it "returns a Token with masked summary + status only, no full PAN (FR-003, FR-004)" do
    stub_request(:get, "#{base}/tokens/tok_ref_1").to_return(status: 200, body: token_json.to_json)

    token = tokens.retrieve("tok_ref_1")

    expect(token.reference).to eq("tok_ref_1")
    expect(token.status).to eq("active")
    expect(token.last4).to eq("4242")
    expect(token.to_h.to_s).not_to match(/\b(?:\d[ -]?){12,19}\b/)
  end

  it "reports a revoked/expired status distinctly (FR-004)" do
    stub_request(:get, "#{base}/tokens/tok_ref_1")
      .to_return(status: 200, body: token_json.merge(status: "revoked").to_json)

    token = tokens.retrieve("tok_ref_1")

    expect(token.status).to eq("revoked")
    expect(token.revoked?).to be(true)
  end

  it "carries auth headers and drops any leaked PAN/CVV on the response" do
    leaky = token_json.merge(card_number: "4111111111111111", cvv: "123")
    stub_request(:get, "#{base}/tokens/tok_ref_1").to_return(status: 200, body: leaky.to_json)

    token = tokens.retrieve("tok_ref_1")

    expect(a_request(:get, "#{base}/tokens/tok_ref_1")
      .with(headers: { "Authorization" => "Bearer key" })).to have_been_made
    serialized = token.to_h.to_s + token.inspect
    expect(serialized).not_to include("4111111111111111")
    expect(token).not_to respond_to(:card_number)
  end

  it "raises a not-found error for an unknown reference (US2-2)" do
    stub_request(:get, "#{base}/tokens/missing").to_return(status: 404, body: "{}")

    expect { tokens.retrieve("missing") }.to raise_error(BmlTokenization::NotFoundError)
  end

  it "maps auth failure → auth error" do
    stub_request(:get, "#{base}/tokens/tok_ref_1").to_return(status: 403, body: "{}")

    expect { tokens.retrieve("tok_ref_1") }.to raise_error(BmlTokenization::AuthenticationError)
  end

  it "emits one retrieve audit record with the token reference (FR-012)" do
    stub_request(:get, "#{base}/tokens/tok_ref_1").to_return(status: 200, body: token_json.to_json)

    tokens.retrieve("tok_ref_1", actor: "auditor-2")

    expect(audit_sink.size).to eq(1)
    expect(audit_sink.first.action).to eq("retrieve")
    expect(audit_sink.first.token_reference).to eq("tok_ref_1")
    expect(audit_sink.first.actor).to include("auditor-2")
  end
end
