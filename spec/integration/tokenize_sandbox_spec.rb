# frozen_string_literal: true

# Opt-in, credential-gated end-to-end tokenize suite against the real BML sandbox
# (FR-014). Skips cleanly when credentials or a single-use handle are absent so
# the deterministic suite stays runnable without secrets. Makes REAL network
# calls, so it enables Net::HTTP only within this file. Requires BML_API_KEY
# (and BML_APP_ID) plus BML_CARD_HANDLE.
RSpec.describe "Tokenization#tokenize sandbox integration", :integration do
  before(:all) do
    @credentials_present = ENV["BML_API_KEY"] && !ENV["BML_API_KEY"].empty? &&
                           ENV["BML_CARD_HANDLE"] && !ENV["BML_CARD_HANDLE"].empty?
    WebMock.allow_net_connect! if @credentials_present
  end

  after(:all) do
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  let(:client) do
    BmlTokenization::Client.new(
      api_key: ENV["BML_API_KEY"],
      app_id: ENV["BML_APP_ID"],
      environment: (ENV["BML_ENV"] || "sandbox").to_sym
    )
  end
  let(:card_handle) { ENV["BML_CARD_HANDLE"] }

  before do
    unless @credentials_present
      skip "Set BML_API_KEY (+ BML_APP_ID) and BML_CARD_HANDLE to run the sandbox integration suite"
    end
  end

  it "tokenizes a valid handle end-to-end, masked-only and in the sandbox environment (US1-1, SC-002)" do
    token = client.tokenization.tokenize(card_handle)

    expect(token).to be_a(BmlTokenization::Token)
    expect(token.reference).not_to be_nil
    expect(token.status).to eq("active")
    expect(token.to_h.to_s).not_to match(/\b(?:\d[ -]?){12,19}\b/) # no full PAN
    expect(token.environment).to eq(:sandbox)
    expect(client.base_url).to include("uat")
  end

  it "is idempotent for the same card + account + environment (FR-011)" do
    first = client.tokenization.tokenize(card_handle)
    second = client.tokenization.tokenize(card_handle)

    expect(second.reference).to eq(first.reference)
  end
end
