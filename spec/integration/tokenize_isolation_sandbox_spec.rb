# frozen_string_literal: true

# Opt-in, credential-gated idempotency-isolation suite (FR-011, SC-006): the same
# card handle tokenized under a DIFFERENT account or environment yields a
# DISTINCT, uncorrelated token — complementing the same-account/same-env "same
# token" check in the tokenize unit/integration specs. Skips cleanly without
# credentials. Requires BML_API_KEY (+ BML_APP_ID) and BML_CARD_HANDLE; a second
# account is supplied via BML_APP_ID_ALT (+ optional BML_API_KEY_ALT).
RSpec.describe "Tokenization idempotency isolation sandbox integration", :integration do
  before(:all) do
    @credentials_present = ENV["BML_API_KEY"] && !ENV["BML_API_KEY"].empty? &&
                           ENV["BML_CARD_HANDLE"] && !ENV["BML_CARD_HANDLE"].empty?
    @alt_account_present = ENV["BML_APP_ID_ALT"] && !ENV["BML_APP_ID_ALT"].empty?
    WebMock.allow_net_connect! if @credentials_present
  end

  after(:all) do
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  let(:card_handle) { ENV["BML_CARD_HANDLE"] }
  let(:primary_client) do
    BmlTokenization::Client.new(api_key: ENV["BML_API_KEY"], app_id: ENV["BML_APP_ID"], environment: :sandbox)
  end
  let(:alt_account_client) do
    BmlTokenization::Client.new(
      api_key: ENV["BML_API_KEY_ALT"] || ENV["BML_API_KEY"],
      app_id: ENV["BML_APP_ID_ALT"],
      environment: :sandbox
    )
  end

  before do
    unless @credentials_present
      skip "Set BML_API_KEY (+ BML_APP_ID) and BML_CARD_HANDLE to run the sandbox integration suite"
    end
  end

  it "yields a distinct, uncorrelated token for the same handle under a different account (SC-006)" do
    skip "Set BML_APP_ID_ALT (a second sandbox account) to run the cross-account isolation check" unless @alt_account_present

    primary = primary_client.tokenization.tokenize(card_handle)
    other = alt_account_client.tokenization.tokenize(card_handle)

    expect(other.reference).not_to eq(primary.reference)
  end
end
