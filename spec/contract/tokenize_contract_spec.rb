# frozen_string_literal: true

# Verifies the public library API contract + the BML remote HTTP contract for
# tokenize (contracts/library-api.md, contracts/bml-remote.md): the create-token
# request carries the handle + auth headers and no PAN/CVV/handle-in-log; the
# response maps to a masked-only Token; a tokenize audit record is emitted.
RSpec.describe "Tokenization#tokenize contract" do
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

  it "is reachable via the client accessor (FR-001)" do
    expect(client.tokenization).to be_a(BmlTokenization::Tokenization)
  end

  it "returns an active Token with a safe reference + masked summary and no full PAN (FR-003, FR-006)" do
    stub_request(:post, "#{base}/tokens").to_return(status: 201, body: token_json.to_json)

    token = tokens.tokenize("handle_123")

    expect(token).to be_a(BmlTokenization::Token)
    expect(token.reference).to eq("tok_ref_1")
    expect(token.status).to eq("active")
    expect(token.last4).to eq("4242")
    expect(token).not_to respond_to(:card_number)
    expect(token.to_h.to_s).not_to match(/\b(?:\d[ -]?){12,19}\b/)
  end

  it "sends only the card_handle (no PAN/CVV/SAD) with auth headers (bml-remote.md)" do
    stub_request(:post, "#{base}/tokens").to_return(status: 201, body: token_json.to_json)

    tokens.tokenize("handle_123")

    expect(
      a_request(:post, "#{base}/tokens")
        .with(headers: { "Authorization" => "Bearer key", "X-App-Id" => "app" }) do |req|
          body = JSON.parse(req.body)
          body.keys == %w[card_handle] &&
            %w[pan card_number cvv cvv2 pin track track1 track2].none? { |k| body.key?(k) } &&
            !req.body.match?(/\b(?:\d[ -]?){12,19}\b/)
        end
    ).to have_been_made
  end

  it "maps a token_reference response field to the Token reference and drops any leaked PAN" do
    stub_request(:post, "#{base}/tokens")
      .to_return(status: 200, body: token_json.merge(card_number: "4242424242424242").to_json)

    token = tokens.tokenize("handle_123")

    expect(token.reference).to eq("tok_ref_1")
    expect(token.to_h.to_s).not_to include("4242424242424242")
  end

  it "tags the Token with the client's configured environment (FR-008)" do
    stub_request(:post, "#{base}/tokens").to_return(status: 201, body: token_json.to_json)

    expect(tokens.tokenize("handle_123").environment).to eq(:sandbox)
  end

  it "emits one tokenize audit record with the token reference and no card data (FR-012)" do
    stub_request(:post, "#{base}/tokens").to_return(status: 201, body: token_json.to_json)

    tokens.tokenize("handle_secret", actor: "user-9")

    expect(audit_sink.size).to eq(1)
    record = audit_sink.first
    expect(record.action).to eq("tokenize")
    expect(record.token_reference).to eq("tok_ref_1")
    expect(record.actor).to include("user-9")
    expect(record.to_h.to_s).not_to include("handle_secret")
  end

  it "maps invalid/consumed/expired handle → validation, auth → auth, timeout/5xx → availability" do
    stub_request(:post, "#{base}/tokens").to_return(status: 422, body: { field: "card_handle" }.to_json)
    expect { tokens.tokenize("bad") }
      .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:card_handle) }

    stub_request(:post, "#{base}/tokens").to_return(status: 401, body: "{}")
    expect { tokens.tokenize("handle_123") }.to raise_error(BmlTokenization::AuthenticationError)

    stub_request(:post, "#{base}/tokens").to_return(status: 503, body: "{}")
    expect { tokens.tokenize("handle_123") }.to raise_error(BmlTokenization::AvailabilityError)
  end

  it "routes a sandbox client to the sandbox base URL and never to production (FR-008)" do
    stub_request(:post, "#{base}/tokens").to_return(status: 201, body: token_json.to_json)

    tokens.tokenize("handle_123")

    expect(a_request(:post, "#{base}/tokens")).to have_been_made
    expect(a_request(:any, %r{//api\.merchants\.bankofmaldives})).not_to have_been_made
  end
end
