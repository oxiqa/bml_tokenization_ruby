# frozen_string_literal: true

# Opt-in, credential-gated end-to-end suite against the real BML sandbox
# (FR-012). Skips cleanly when credentials or a single-use card handle are
# absent so the deterministic suite stays runnable without secrets. These specs
# make REAL network calls, so they enable Net::HTTP connections only within this
# file. Requires BML_API_KEY (and BML_APP_ID) plus BML_CARD_HANDLE.
RSpec.describe "CardsOnFile sandbox integration", :integration do
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
  let(:customer_id) { ENV["BML_CUSTOMER_ID"] || "it-customer" }
  let(:card_handle) { ENV["BML_CARD_HANDLE"] }

  before do
    unless @credentials_present
      skip "Set BML_API_KEY (+ BML_APP_ID) and BML_CARD_HANDLE to run the sandbox integration suite"
    end
  end

  it "stores a card end-to-end in the sandbox environment, isolated from production (US1-3, SC-005)" do
    card = client.cards_on_file.store(customer_id: customer_id, card_handle: card_handle)

    expect(card).to be_a(BmlTokenization::CardOnFile)
    expect(card.reference).not_to be_nil
    expect(card.to_h.to_s).not_to match(/\b(?:\d[ -]?){12,19}\b/) # no full PAN
    expect(client.environment).to eq(:sandbox)
    expect(client.base_url).to include("uat")
  end

  it "re-stores the same card idempotently (no duplicate) (FR-013, US1-3)" do
    first = client.cards_on_file.store(customer_id: customer_id, card_handle: card_handle)
    second = client.cards_on_file.store(customer_id: customer_id, card_handle: card_handle)

    expect(second.reference).to eq(first.reference)
  end

  it "lists a customer's cards, and returns an empty list for a customer with none (US2-1, US2-2)" do
    client.cards_on_file.store(customer_id: customer_id, card_handle: card_handle)

    listed = client.cards_on_file.list(customer_id: customer_id)
    expect(listed).to be_a(BmlTokenization::CardOnFileList)

    empty = client.cards_on_file.list(customer_id: "it-customer-with-no-cards-#{Process.pid}")
    expect(empty).to be_empty
  end

  it "stores then retrieves the same card, with expiry discoverable (US3-1)" do
    stored = client.cards_on_file.store(customer_id: customer_id, card_handle: card_handle)

    fetched = client.cards_on_file.retrieve(stored.reference)

    expect(fetched.reference).to eq(stored.reference)
    expect(fetched).to respond_to(:expired?)
  end

  it "removes a card so it is gone from the list and not-found on retrieval (US4-1, SC-004)" do
    stored = client.cards_on_file.store(customer_id: customer_id, card_handle: card_handle)

    expect(client.cards_on_file.remove(stored.reference)).to be(true)
    expect { client.cards_on_file.retrieve(stored.reference) }
      .to raise_error(BmlTokenization::NotFoundError)
    expect(client.cards_on_file.list(customer_id: customer_id).map(&:reference))
      .not_to include(stored.reference)
  end
end
