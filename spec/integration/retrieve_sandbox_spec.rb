# frozen_string_literal: true

# Opt-in, credential-gated end-to-end retrieve suite against the real BML sandbox
# (FR-014). Skips cleanly without credentials. Requires BML_API_KEY (and
# BML_APP_ID) plus BML_CARD_HANDLE.
RSpec.describe "Tokenization#retrieve sandbox integration", :integration do
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

  it "tokenizes then retrieves the same token with masked summary + status (US2-1)" do
    issued = client.tokenization.tokenize(card_handle)

    fetched = client.tokenization.retrieve(issued.reference)

    expect(fetched.reference).to eq(issued.reference)
    expect(BmlTokenization::Token::STATUSES).to include(fetched.status)
    expect(fetched.to_h.to_s).not_to match(/\b(?:\d[ -]?){12,19}\b/)
  end

  it "raises a not-found error for an unknown reference (US2-2)" do
    expect { client.tokenization.retrieve("tok_does_not_exist_#{Process.pid}") }
      .to raise_error(BmlTokenization::NotFoundError)
  end
end
