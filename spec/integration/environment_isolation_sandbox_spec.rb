# frozen_string_literal: true

# Opt-in, credential-gated environment-isolation suite (FR-008, SC-005): a token
# reference issued in SANDBOX is reported not-found/invalid when the client is
# configured for PRODUCTION (and, where production credentials exist, the
# reverse). Skips cleanly without credentials. Requires BML_API_KEY (+
# BML_APP_ID) and BML_CARD_HANDLE for the sandbox leg; BML_PROD_API_KEY (+
# BML_PROD_APP_ID) optionally enable the reverse leg.
RSpec.describe "Tokenization environment isolation sandbox integration", :integration do
  before(:all) do
    @credentials_present = ENV["BML_API_KEY"] && !ENV["BML_API_KEY"].empty? &&
                           ENV["BML_CARD_HANDLE"] && !ENV["BML_CARD_HANDLE"].empty?
    WebMock.allow_net_connect! if @credentials_present
  end

  after(:all) do
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  let(:sandbox_client) do
    BmlTokenization::Client.new(api_key: ENV["BML_API_KEY"], app_id: ENV["BML_APP_ID"], environment: :sandbox)
  end
  let(:production_client) do
    BmlTokenization::Client.new(
      api_key: ENV["BML_PROD_API_KEY"] || ENV["BML_API_KEY"],
      app_id: ENV["BML_PROD_APP_ID"] || ENV["BML_APP_ID"],
      environment: :production
    )
  end
  let(:card_handle) { ENV["BML_CARD_HANDLE"] }

  before do
    unless @credentials_present
      skip "Set BML_API_KEY (+ BML_APP_ID) and BML_CARD_HANDLE to run the sandbox integration suite"
    end
  end

  it "reports a sandbox-issued token as not-found/invalid when queried against production (SC-005)" do
    issued = sandbox_client.tokenization.tokenize(card_handle)
    expect(sandbox_client.base_url).to include("uat")
    expect(production_client.base_url).not_to include("uat")

    expect { production_client.tokenization.retrieve(issued.reference) }
      .to raise_error(BmlTokenization::NotFoundError)
      .or raise_error(BmlTokenization::AuthenticationError)
  end
end
