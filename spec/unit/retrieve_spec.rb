# frozen_string_literal: true

# Unit spec for Tokenization#retrieve: local validation (FR-007), unknown
# reference → not-found (FR-010), and the returned Token exposes no full PAN via
# any accessor or inspect (FR-004, US2-2).
RSpec.describe "BmlTokenization::Tokenization#retrieve" do
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

  it "rejects a blank/nil reference before any remote call (FR-007)" do
    expect { tokens.retrieve(nil) }
      .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:reference) }
    expect { tokens.retrieve("  ") }
      .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:reference) }
    expect(a_request(:any, /tokens/)).not_to have_been_made
  end

  it "maps an unknown reference to a not-found error (US2-2)" do
    stub_request(:get, "#{base}/tokens/missing").to_return(status: 404, body: "{}")

    expect { tokens.retrieve("missing") }.to raise_error(BmlTokenization::NotFoundError)
  end

  it "returns a Token that exposes no full PAN via any accessor or inspect (US2-2)" do
    leaky = token_json.merge(card_number: "4111111111111111", cvv: "123", card_handle: "tok_x")
    stub_request(:get, "#{base}/tokens/tok_ref_1").to_return(status: 200, body: leaky.to_json)

    token = tokens.retrieve("tok_ref_1")

    serialized = token.to_h.to_s + token.inspect
    expect(serialized).not_to include("4111111111111111")
    expect(serialized).not_to include("tok_x")
    expect(token).not_to respond_to(:card_number)
  end
end
