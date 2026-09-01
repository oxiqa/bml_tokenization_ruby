# frozen_string_literal: true

# Unit spec for the Transactions resource: local (pre-remote) create validation,
# idempotency + conflict on the global reference, retrieve/list behaviour, and no
# PAN/CVV or payment-URL leakage across any output, log, or audit record
# (FR-005, FR-006, FR-010, FR-012, FR-013, SC-005, SC-007).
RSpec.describe BmlTokenization::Transactions do
  let(:base) { BmlTokenization::Client::BASE_URLS[:sandbox] }
  let(:audit_sink) { [] }
  let(:logger) { instance_double("Logger", info: nil) }
  let(:client) do
    BmlTokenization::Client.new(
      api_key: "key", app_id: "app", environment: :sandbox,
      retry_backoff: 0, audit_sink: audit_sink, logger: logger
    )
  end
  let(:transactions) { client.transactions }

  let(:valid_redirect) do
    { customer_id: "cus_1", amount: 15_000, currency: "MVR", reference: "order-1",
      return_url: "https://merchant.example/return" }
  end
  let(:redirect_response) do
    { id: "txn_1", reference: "order-1", customer_id: "cus_1", amount: 15_000,
      currency: "MVR", status: "pending", payment_url: "https://connect.bml.example/pay/txn_1" }
  end

  # ---- Create: pre-remote validation (FR-005, no network call on failure) ----
  describe "create local validation runs before any remote call (FR-005)" do
    %i[customer_id amount currency reference].each do |field|
      it "rejects a missing #{field}, naming the field, with NO network call (FR-005a)" do
        expect { transactions.create(valid_redirect.merge(field => nil)) }
          .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(field) }
        expect(a_request(:any, /transactions/)).not_to have_been_made
      end
    end

    it "rejects a blank required string field with no network call" do
      expect { transactions.create(valid_redirect.merge(reference: "   ")) }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:reference) }
      expect(a_request(:any, /transactions/)).not_to have_been_made
    end

    [0, -1, 100.5, "15000", nil].each do |bad|
      it "rejects a non-positive/non-integer amount (#{bad.inspect}) naming amount (FR-005b)" do
        expect { transactions.create(valid_redirect.merge(amount: bad)) }
          .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:amount) }
        expect(a_request(:any, /transactions/)).not_to have_been_made
      end
    end

    %w[USD EUR mvr Mvr].each do |bad|
      it "rejects a non-MVR currency (#{bad.inspect}) naming currency (FR-005c)" do
        expect { transactions.create(valid_redirect.merge(currency: bad)) }
          .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:currency) }
        expect(a_request(:any, /transactions/)).not_to have_been_made
      end
    end

    it "requires return_url on the redirect path (no card_reference), naming return_url (FR-002)" do
      expect { transactions.create(valid_redirect.merge(return_url: nil)) }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:return_url) }
      expect(a_request(:any, /transactions/)).not_to have_been_made
    end

    it "does NOT require return_url on the stored-card path" do
      stored_card = { id: "txn_9", reference: "order-x", customer_id: "cus_1", amount: 15_000,
                      currency: "MVR", status: "succeeded", card_reference: "cof_1" }
      stub_request(:post, "#{base}/transactions").to_return(status: 201, body: stored_card.to_json)

      expect do
        transactions.create(customer_id: "cus_1", amount: 15_000, currency: "MVR",
                            reference: "order-x", card_reference: "cof_1")
      end.not_to raise_error
    end
  end

  # ---- Create: idempotency + conflict on the global reference (FR-013) ----
  describe "idempotency and conflict on the global reference (FR-013, SC-007)" do
    it "returns the existing transaction on an identical replay (no second charge)" do
      stub_request(:post, "#{base}/transactions").to_return(status: 409, body: redirect_response.to_json)

      txn = transactions.create(valid_redirect)

      expect(txn.id).to eq("txn_1")
      expect(a_request(:post, "#{base}/transactions")).to have_been_made.times(1)
    end

    it "raises a conflict naming the mismatch when a reused reference carries a differing amount" do
      existing = redirect_response.merge(amount: 99_999)
      stub_request(:post, "#{base}/transactions").to_return(status: 409, body: existing.to_json)

      expect { transactions.create(valid_redirect) }
        .to raise_error(BmlTokenization::ConflictError, /amount/)
    end

    it "treats the reference as global: a reused reference under a different customer is a conflict" do
      existing = redirect_response.merge(customer_id: "cus_OTHER")
      stub_request(:post, "#{base}/transactions").to_return(status: 409, body: existing.to_json)

      expect { transactions.create(valid_redirect) }
        .to raise_error(BmlTokenization::ConflictError, /customer/)
    end

    it "re-raises a bare conflict that carries no existing record" do
      stub_request(:post, "#{base}/transactions").to_return(status: 409, body: { error: "conflict" }.to_json)

      expect { transactions.create(valid_redirect) }.to raise_error(BmlTokenization::ConflictError)
    end
  end

  # ---- Retrieve (US2) ----
  describe "retrieve (FR-003, FR-006)" do
    it "returns the current transaction with a distinguishable pending status" do
      stub_request(:get, "#{base}/transactions/txn_1").to_return(status: 200, body: redirect_response.to_json)

      txn = transactions.retrieve("txn_1")

      expect(txn.id).to eq("txn_1")
      expect(txn.status).to eq("pending")
    end

    it "raises not-found for an unknown id (US2-2)" do
      stub_request(:get, "#{base}/transactions/missing").to_return(status: 404, body: "{}")

      expect { transactions.retrieve("missing") }.to raise_error(BmlTokenization::NotFoundError)
    end

    it "rejects a blank id with no network call" do
      expect { transactions.retrieve("") }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:id) }
      expect(a_request(:any, /transactions/)).not_to have_been_made
    end
  end

  # ---- List validation (US3) ----
  describe "list validation (FR-004, R7)" do
    it "rejects a page_size over 100 pre-remote, naming page_size" do
      expect { transactions.list(page_size: 101) }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:page_size) }
      expect(a_request(:any, /transactions/)).not_to have_been_made
    end

    it "rejects an unrecognized status filter pre-remote, naming status" do
      expect { transactions.list(status: "bogus") }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:status) }
      expect(a_request(:any, /transactions/)).not_to have_been_made
    end

    it "returns an empty page (not an error) when no records match" do
      stub_request(:get, "#{base}/transactions").with(query: hash_including({}))
                                                .to_return(status: 200, body: { records: [], page: 9999 }.to_json)

      expect(transactions.list(page: 9999)).to be_empty
    end
  end

  # ---- Audit emission: create + retrieve only; list is not audited (FR-012) ----
  describe "audit emission (FR-012)" do
    it "emits a create and a retrieve audit record, but none for list" do
      stub_request(:post, "#{base}/transactions").to_return(status: 201, body: redirect_response.to_json)
      stub_request(:get, "#{base}/transactions/txn_1").to_return(status: 200, body: redirect_response.to_json)
      stub_request(:get, "#{base}/transactions").with(query: hash_including({}))
                                                .to_return(status: 200, body: { records: [] }.to_json)

      transactions.create(valid_redirect, actor: "user-7")
      transactions.retrieve("txn_1")
      transactions.list

      expect(audit_sink.map(&:action)).to eq(%w[create retrieve])
      create_record = audit_sink.first
      expect(create_record.transaction_id).to eq("txn_1")
      expect(create_record.reference).to eq("order-1")
      expect(create_record.actor).to include("user-7")
    end
  end

  # ---- T030: no PAN/CVV or payment-URL leakage across create/retrieve/list ----
  describe "no PAN/CVV or payment-URL leakage across operations (FR-010, SC-005, R11)" do
    it "never leaks card data the platform returns, on any output" do
      leaky = redirect_response.merge(card_number: "4111111111111111", cvv: "123")
      stub_request(:get, "#{base}/transactions/txn_1").to_return(status: 200, body: leaky.to_json)

      txn = transactions.retrieve("txn_1")

      serialized = txn.to_h.to_s + txn.inspect
      expect(serialized).not_to include("4111111111111111")
      expect(serialized).not_to include("\"123\"")
      expect(txn).not_to respond_to(:card_number)
    end

    it "never logs the hosted payment URL, and never puts it (or card data) in an audit record" do
      logged = []
      allow(logger).to receive(:info) { |entry| logged << entry }
      stub_request(:post, "#{base}/transactions").to_return(status: 201, body: redirect_response.to_json)

      transactions.create(valid_redirect, actor: "user-1")

      dump = logged.map(&:to_s).join
      expect(dump).not_to include("connect.bml.example") # payment_url never logged verbatim
      expect(dump).to include("order-1") # safe reference is logged

      audit_dump = audit_sink.first.to_h.to_s
      expect(audit_dump).not_to include("connect.bml.example")
      expect(audit_dump).not_to match(/\b(?:\d[ -]?){12,19}\b/)
    end
  end
end
