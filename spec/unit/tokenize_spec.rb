# frozen_string_literal: true

# Unit spec for Tokenization#tokenize: local validation before any remote call
# (FR-007), PAN-looking actor rejection (FR-012a), and per-account/per-environment
# idempotency — the same card returns the existing token, never a duplicate
# (FR-011).
RSpec.describe "BmlTokenization::Tokenization#tokenize" do
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

  describe "local validation runs before any remote call (FR-007)" do
    it "rejects a nil/blank handle, naming the field, with NO network call" do
      expect { tokens.tokenize(nil) }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:card_handle) }
      expect { tokens.tokenize("   ") }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:card_handle) }
      expect(a_request(:any, /tokens/)).not_to have_been_made
    end

    it "rejects a PAN-looking actor before any remote call (FR-012a)" do
      expect { tokens.tokenize("handle_123", actor: "4111 1111 1111 1111") }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:actor) }
      expect(a_request(:any, /tokens/)).not_to have_been_made
    end
  end

  describe "idempotency per account + environment (FR-011)" do
    it "returns the existing token (no duplicate) when the platform reports a 409 with the reference" do
      stub_request(:post, "#{base}/tokens").to_return(status: 409, body: token_json.to_json)

      token = tokens.tokenize("handle_123")

      expect(token.reference).to eq("tok_ref_1")
      # exactly one POST — the library did not attempt a second create
      expect(a_request(:post, "#{base}/tokens")).to have_been_made.times(1)
    end

    it "re-raises a genuine conflict that carries no existing token reference" do
      stub_request(:post, "#{base}/tokens").to_return(status: 409, body: { error: "conflict" }.to_json)

      expect { tokens.tokenize("handle_123") }.to raise_error(BmlTokenization::ConflictError)
    end
  end

  describe "audit + masking" do
    it "emits a tokenize audit record whose serialization contains no handle/PAN" do
      stub_request(:post, "#{base}/tokens").to_return(status: 201, body: token_json.to_json)

      tokens.tokenize("handle_secret_value")

      dump = audit_sink.first.to_h.to_s
      expect(dump).not_to include("handle_secret_value")
      expect(dump).to include("tok_ref_1")
    end

    it "never logs the single-use handle" do
      logger = instance_double("Logger")
      logged = []
      allow(logger).to receive(:info) { |entry| logged << entry }
      configured = BmlTokenization::Client.new(
        api_key: "key", app_id: "app", environment: :sandbox, retry_backoff: 0, logger: logger
      )
      stub_request(:post, "#{base}/tokens").to_return(status: 201, body: token_json.to_json)

      configured.tokenization.tokenize("handle_secret_value")

      dump = logged.map(&:to_s).join
      expect(dump).not_to include("handle_secret_value")
      expect(dump).to include("tok_ref_1")
    end
  end
end
