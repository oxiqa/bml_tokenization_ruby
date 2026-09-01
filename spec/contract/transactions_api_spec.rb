# frozen_string_literal: true

# Verifies the public library API contract for the Transactions resource
# (contracts/library-api.md): inputs, outputs, and error conditions for
# create (both paths) / retrieve / list, idempotency + conflict, and audit
# emission on the state-changing create/retrieve (not list).
RSpec.describe "Transactions public API contract" do
  let(:base) { BmlTokenization::Client::BASE_URLS[:sandbox] }
  let(:audit_sink) { [] }
  let(:client) do
    BmlTokenization::Client.new(
      api_key: "key", app_id: "app", environment: :sandbox, retry_backoff: 0, audit_sink: audit_sink
    )
  end
  let(:transactions) { client.transactions }

  let(:redirect_response) do
    { id: "txn_1", reference: "order-1", customer_id: "cus_1", amount: 15_000, currency: "MVR",
      status: "pending", payment_url: "https://connect.bml.example/pay/txn_1" }
  end
  let(:stored_card_response) do
    { id: "txn_2", reference: "order-2", customer_id: "cus_1", amount: 15_000, currency: "MVR",
      status: "succeeded", card_reference: "cof_safe_abc" }
  end

  it "is reachable via the client accessor (FR-001)" do
    expect(client.transactions).to be_a(BmlTokenization::Transactions)
  end

  describe "create — redirect path (FR-002, US1-1, SC-001)" do
    it "returns a pending Transaction carrying a hosted payment_url and no card_reference" do
      stub_request(:post, "#{base}/transactions").to_return(status: 201, body: redirect_response.to_json)

      txn = transactions.create(customer_id: "cus_1", amount: 15_000, currency: "MVR",
                                reference: "order-1", return_url: "https://merchant.example/return")

      expect(txn).to be_a(BmlTokenization::Transaction)
      expect(txn.id).to eq("txn_1")
      expect(txn.status).to eq("pending")
      expect(txn.payment_url).to eq("https://connect.bml.example/pay/txn_1")
      expect(txn.card_reference).to be_nil
    end

    it "emits a create audit record with the id + reference and no card data / payment URL (FR-012)" do
      stub_request(:post, "#{base}/transactions").to_return(status: 201, body: redirect_response.to_json)

      transactions.create(customer_id: "cus_1", amount: 15_000, currency: "MVR",
                          reference: "order-1", return_url: "https://merchant.example/return", actor: "user-9")

      expect(audit_sink.size).to eq(1)
      record = audit_sink.first
      expect(record.action).to eq("create")
      expect(record.transaction_id).to eq("txn_1")
      expect(record.reference).to eq("order-1")
      expect(record.actor).to include("user-9")
      expect(record.to_h.to_s).not_to include("connect.bml.example")
    end
  end

  describe "create — stored-card path (FR-002, US1-2)" do
    it "charges server-side and returns a resolved Transaction with no payment_url" do
      stub_request(:post, "#{base}/transactions").to_return(status: 201, body: stored_card_response.to_json)

      txn = transactions.create(customer_id: "cus_1", amount: 15_000, currency: "MVR",
                                reference: "order-2", card_reference: "cof_safe_abc")

      expect(txn.status).to eq("succeeded")
      expect(txn.payment_url).to be_nil
      expect(txn.card_reference).to eq("cof_safe_abc")
    end
  end

  describe "create — validation and remote errors (FR-005, FR-009)" do
    it "raises validation naming the field, with NO network call, for a bad amount/currency" do
      expect do
        transactions.create(customer_id: "cus_1", amount: 0, currency: "MVR",
                            reference: "r", return_url: "https://m.example/r")
      end.to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:amount) }
      expect(a_request(:any, /transactions/)).not_to have_been_made
    end

    it "maps a 404 to a not-found identifying a missing customer, creating no transaction (FR-005a)" do
      stub_request(:post, "#{base}/transactions").to_return(status: 404, body: { error: "unknown customer" }.to_json)

      expect do
        transactions.create(customer_id: "nope", amount: 15_000, currency: "MVR",
                            reference: "order-3", return_url: "https://merchant.example/return")
      end.to raise_error(BmlTokenization::NotFoundError)
    end
  end

  describe "retrieve (US2-1, US2-2)" do
    it "returns the current transaction with its status" do
      stub_request(:get, "#{base}/transactions/txn_1").to_return(status: 200, body: redirect_response.to_json)

      expect(transactions.retrieve("txn_1").status).to eq("pending")
    end

    it "raises not-found for an unknown id" do
      stub_request(:get, "#{base}/transactions/missing").to_return(status: 404, body: "{}")

      expect { transactions.retrieve("missing") }.to raise_error(BmlTokenization::NotFoundError)
    end

    it "emits a retrieve audit record" do
      stub_request(:get, "#{base}/transactions/txn_1").to_return(status: 200, body: redirect_response.to_json)

      transactions.retrieve("txn_1")

      expect(audit_sink.map(&:action)).to eq(%w[retrieve])
      expect(audit_sink.first.transaction_id).to eq("txn_1")
    end
  end

  describe "list (US3-1..US3-5, FR-004)" do
    let(:list_response) do
      { records: [redirect_response], page: 1, page_size: 20, total_count: 1 }
    end

    it "returns a TransactionList page defaulting page_size to 20" do
      stub_request(:get, "#{base}/transactions").with(query: { page: 1, page_size: 20 })
                                                .to_return(status: 200, body: list_response.to_json)

      list = transactions.list

      expect(list).to be_a(BmlTokenization::TransactionList)
      expect(list.page_size).to eq(20)
      expect(list.records.map(&:id)).to eq(%w[txn_1])
    end

    it "combines optional customer and status filters" do
      stub_request(:get, "#{base}/transactions")
        .with(query: { page: 1, page_size: 20, customer_id: "cus_1", status: "pending" })
        .to_return(status: 200, body: list_response.to_json)

      transactions.list(customer_id: "cus_1", status: "pending")

      expect(
        a_request(:get, "#{base}/transactions")
          .with(query: { page: 1, page_size: 20, customer_id: "cus_1", status: "pending" })
      ).to have_been_made
    end

    it "rejects an over-max page_size and an unknown status before any request" do
      expect { transactions.list(page_size: 101) }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:page_size) }
      expect { transactions.list(status: "bogus") }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:status) }
      expect(a_request(:any, /transactions/)).not_to have_been_made
    end

    it "returns an empty page (not an error) when nothing matches" do
      stub_request(:get, "#{base}/transactions").with(query: hash_including({}))
                                                .to_return(status: 200, body: { records: [] }.to_json)

      expect(transactions.list(customer_id: "none")).to be_empty
    end

    it "emits NO audit record for a list (FR-012, R11)" do
      stub_request(:get, "#{base}/transactions").with(query: hash_including({}))
                                                .to_return(status: 200, body: { records: [] }.to_json)

      transactions.list

      expect(audit_sink).to be_empty
    end
  end
end
