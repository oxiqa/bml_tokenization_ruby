# frozen_string_literal: true

# Verifies the public library API + BML remote HTTP contract for revoke
# (contracts/*, FR-005a): revoke issues a single call to the token's own revoke
# endpoint and NO additional call that would mutate any other resource
# (no-cascade); unknown/already-revoked map to distinguishable errors; a revoke
# audit record is emitted.
RSpec.describe "Tokenization#revoke contract" do
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

  it "permanently invalidates the token, returning a terminal revoked Token (FR-005)" do
    stub_request(:post, "#{base}/tokens/tok_ref_1/revoke").to_return(status: 200, body: revoked_json.to_json)

    token = tokens.revoke("tok_ref_1")

    expect(token.status).to eq("revoked")
    expect(token.revoked?).to be(true)
  end

  it "issues NO call that mutates card-on-file or transaction resources — no cascade (FR-005a)" do
    stub_request(:post, "#{base}/tokens/tok_ref_1/revoke").to_return(status: 200, body: revoked_json.to_json)

    tokens.revoke("tok_ref_1")

    # exactly one request in total, and none to any other resource
    expect(a_request(:post, "#{base}/tokens/tok_ref_1/revoke")).to have_been_made.times(1)
    expect(a_request(:any, /cards-on-file/)).not_to have_been_made
    expect(a_request(:any, /transactions/)).not_to have_been_made
    expect(a_request(:delete, /tokens/)).not_to have_been_made
  end

  it "carries auth headers on the revoke request" do
    stub_request(:post, "#{base}/tokens/tok_ref_1/revoke").to_return(status: 200, body: revoked_json.to_json)

    tokens.revoke("tok_ref_1")

    expect(a_request(:post, "#{base}/tokens/tok_ref_1/revoke")
      .with(headers: { "Authorization" => "Bearer key", "X-App-Id" => "app" })).to have_been_made
  end

  it "maps an unknown reference → not-found and an already-revoked → conflict (US3-2)" do
    stub_request(:post, "#{base}/tokens/missing/revoke").to_return(status: 404, body: "{}")
    expect { tokens.revoke("missing") }.to raise_error(BmlTokenization::NotFoundError)

    stub_request(:post, "#{base}/tokens/tok_ref_1/revoke").to_return(status: 409, body: "{}")
    expect { tokens.revoke("tok_ref_1") }.to raise_error(BmlTokenization::ConflictError)
  end

  it "maps auth failure → auth error" do
    stub_request(:post, "#{base}/tokens/tok_ref_1/revoke").to_return(status: 401, body: "{}")

    expect { tokens.revoke("tok_ref_1") }.to raise_error(BmlTokenization::AuthenticationError)
  end

  it "emits one revoke audit record with the token reference and no card data (FR-012)" do
    stub_request(:post, "#{base}/tokens/tok_ref_1/revoke").to_return(status: 200, body: revoked_json.to_json)

    tokens.revoke("tok_ref_1", actor: "admin-3")

    expect(audit_sink.size).to eq(1)
    record = audit_sink.first
    expect(record.action).to eq("revoke")
    expect(record.token_reference).to eq("tok_ref_1")
    expect(record.actor).to include("admin-3")
    expect(record.to_h.to_s).not_to match(/\b(?:\d[ -]?){12,19}\b/)
  end
end
