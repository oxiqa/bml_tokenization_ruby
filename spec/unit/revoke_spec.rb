# frozen_string_literal: true

# Unit spec for Tokenization#revoke: local validation (FR-007), permanence with
# no reactivation, already-revoked → error, and no-cascade — the referencing
# card-on-file / transaction records are never touched (FR-005, FR-005a, US3-2,
# US3-3).
RSpec.describe "BmlTokenization::Tokenization#revoke" do
  let(:base) { BmlTokenization::Client::BASE_URLS[:sandbox] }
  let(:audit_sink) { [] }
  let(:client) do
    BmlTokenization::Client.new(
      api_key: "key", app_id: "app", environment: :sandbox, retry_backoff: 0, audit_sink: audit_sink
    )
  end
  let(:tokens) { client.tokenization }
  let(:revoked_json) do
    { token_reference: "tok_ref_1", scheme: "visa", last4: "4242",
      expiry_month: 12, expiry_year: 2028, status: "revoked" }
  end

  it "rejects a blank/nil reference before any remote call (FR-007)" do
    expect { tokens.revoke(nil) }
      .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:reference) }
    expect { tokens.revoke("  ") }
      .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:reference) }
    expect(a_request(:any, /tokens/)).not_to have_been_made
  end

  it "yields a terminal revoked token — the library never reactivates it (FR-005)" do
    stub_request(:post, "#{base}/tokens/tok_ref_1/revoke").to_return(status: 200, body: revoked_json.to_json)

    token = tokens.revoke("tok_ref_1")

    expect(token.revoked?).to be(true)
    expect(token.active?).to be(false)
  end

  it "surfaces an already-revoked token as a distinguishable conflict error (US3-2)" do
    stub_request(:post, "#{base}/tokens/tok_ref_1/revoke").to_return(status: 409, body: "{}")

    expect { tokens.revoke("tok_ref_1") }.to raise_error(BmlTokenization::ConflictError)
  end

  it "performs no cascade: only the token's revoke endpoint is called (FR-005a, US3-3)" do
    stub_request(:post, "#{base}/tokens/tok_ref_1/revoke").to_return(status: 200, body: revoked_json.to_json)

    tokens.revoke("tok_ref_1")

    expect(a_request(:any, /cards-on-file/)).not_to have_been_made
    expect(a_request(:any, /transactions/)).not_to have_been_made
    # the sole request is the single revoke POST
    expect(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.size).to eq(1)
  end
end
