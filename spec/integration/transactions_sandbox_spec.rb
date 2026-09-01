# frozen_string_literal: true

# Opt-in, credential-gated end-to-end suite against the real BML sandbox
# (FR-011). Skips cleanly when credentials are absent so the deterministic suite
# stays runnable without secrets. These specs make REAL network calls, so they
# enable Net::HTTP connections only within this file. Requires BML_API_KEY (and
# BML_APP_ID) plus BML_CUSTOMER_ID; BML_CARD_REFERENCE enables the stored-card path.
RSpec.describe "Transactions sandbox integration", :integration do
  before(:all) do
    @credentials_present = ENV["BML_API_KEY"] && !ENV["BML_API_KEY"].empty? &&
                           ENV["BML_CUSTOMER_ID"] && !ENV["BML_CUSTOMER_ID"].empty?
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
  let(:customer_id) { ENV["BML_CUSTOMER_ID"] }
  let(:return_url) { ENV["BML_RETURN_URL"] || "https://merchant.example/return" }
  let(:reference) { "it-txn-#{Process.pid}-#{customer_id}" }

  before do
    unless @credentials_present
      skip "Set BML_API_KEY (+ BML_APP_ID) and BML_CUSTOMER_ID to run the sandbox integration suite"
    end
  end

  it "creates a redirect-path transaction, isolated to sandbox, with a payment URL (US1-1, SC-006)" do
    txn = client.transactions.create(
      customer_id: customer_id, amount: 15_000, currency: "MVR", reference: reference, return_url: return_url
    )

    expect(txn).to be_a(BmlTokenization::Transaction)
    expect(txn.id).not_to be_nil
    expect(txn.status).to eq("pending")
    expect(txn.payment_url).not_to be_nil
    expect(txn.to_h.to_s).not_to match(/\b(?:\d[ -]?){12,19}\b/) # no full PAN
    expect(client.environment).to eq(:sandbox)
    expect(client.base_url).to include("uat")
  end

  it "creates then retrieves the same transaction, with a distinguishable status (US2-1)" do
    created = client.transactions.create(
      customer_id: customer_id, amount: 15_000, currency: "MVR", reference: reference, return_url: return_url
    )

    fetched = client.transactions.retrieve(created.id)

    expect(fetched.id).to eq(created.id)
    expect(%w[pending succeeded failed cancelled]).to include(fetched.status)
  end

  it "replays an identical create idempotently (no duplicate) (FR-013, SC-007)" do
    first = client.transactions.create(
      customer_id: customer_id, amount: 15_000, currency: "MVR", reference: reference, return_url: return_url
    )
    second = client.transactions.create(
      customer_id: customer_id, amount: 15_000, currency: "MVR", reference: reference, return_url: return_url
    )

    expect(second.id).to eq(first.id)
  end

  it "lists transactions and returns an empty page beyond the results (US3-1, US3-5)" do
    listed = client.transactions.list(customer_id: customer_id)
    expect(listed).to be_a(BmlTokenization::TransactionList)

    expect(client.transactions.list(customer_id: customer_id, page: 9_999)).to be_empty
  end

  it "charges the stored-card path when a card reference is provided (US1-2)" do
    skip "Set BML_CARD_REFERENCE to exercise the stored-card charge path" unless ENV["BML_CARD_REFERENCE"]

    txn = client.transactions.create(
      customer_id: customer_id, amount: 15_000, currency: "MVR",
      reference: "#{reference}-card", card_reference: ENV["BML_CARD_REFERENCE"]
    )

    expect(%w[succeeded failed]).to include(txn.status)
    expect(txn.payment_url).to be_nil
  end
end
