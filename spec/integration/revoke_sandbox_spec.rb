# frozen_string_literal: true

# Opt-in, credential-gated end-to-end revoke suite against the real BML sandbox
# (FR-014). Skips cleanly without credentials. Requires BML_API_KEY (and
# BML_APP_ID) plus BML_CARD_HANDLE.
RSpec.describe "Tokenization#revoke sandbox integration", :integration do
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

  it "revokes a token so it reports revoked and is not reactivated (US3-1, SC-004)" do
    issued = client.tokenization.tokenize(card_handle)

    revoked = client.tokenization.revoke(issued.reference)
    expect(revoked.revoked?).to be(true)

    # the token is still retrievable (no deletion) and reports the terminal status
    fetched = client.tokenization.retrieve(issued.reference)
    expect(fetched.revoked?).to be(true)
  end

  it "rejects revoking an already-revoked or unknown token (US3-2)" do
    expect { client.tokenization.revoke("tok_does_not_exist_#{Process.pid}") }
      .to raise_error(BmlTokenization::NotFoundError).or raise_error(BmlTokenization::ConflictError)
  end
end
