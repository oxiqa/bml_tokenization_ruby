# frozen_string_literal: true

# Verifies conformance to the remote BML HTTP contract (contracts/bml-remote.md)
# using WebMock stubs — no live credentials required. Covers both create request
# shapes, the response->library mapping, idempotency/conflict, error mapping,
# environment isolation, and the transient-failure / rate-limit resilience.
RSpec.describe "Transactions remote HTTP contract" do
  let(:sandbox_base) { BmlTokenization::Client::BASE_URLS[:sandbox] }
  let(:production_base) { BmlTokenization::Client::BASE_URLS[:production] }
  let(:client) do
    BmlTokenization::Client.new(api_key: "key", app_id: "app", environment: :sandbox, retry_backoff: 0)
  end
  let(:transactions) { client.transactions }

  let(:redirect_response) do
    { id: "txn_1", reference: "order-1", customer_id: "cus_1", amount: 15_000, currency: "MVR",
      status: "pending", payment_url: "https://connect.bml.example/pay/txn_1" }
  end

  describe "create — POST /transactions" do
    it "sends the redirect-path request shape (return_url, no card_reference) with auth headers, no card data" do
      stub_request(:post, "#{sandbox_base}/transactions").to_return(status: 201, body: redirect_response.to_json)

      transactions.create(customer_id: "cus_1", amount: 15_000, currency: "MVR",
                          reference: "order-1", return_url: "https://merchant.example/return")

      expect(
        a_request(:post, "#{sandbox_base}/transactions")
          .with(headers: { "Authorization" => "Bearer key", "X-App-Id" => "app" }) do |req|
            body = JSON.parse(req.body)
            body.keys.sort == %w[amount currency customer_id reference return_url] &&
              body["currency"] == "MVR" &&
              %w[pan card_number cvv cvv2 pin card_reference].none? { |k| body.key?(k) } &&
              !req.body.match?(/\b(?:\d[ -]?){12,19}\b/)
          end
      ).to have_been_made
    end

    it "sends the stored-card request shape (card_reference, no return_url)" do
      stub_request(:post, "#{sandbox_base}/transactions")
        .to_return(status: 201, body: redirect_response.merge(card_reference: "cof_1", status: "succeeded").to_json)

      transactions.create(customer_id: "cus_1", amount: 15_000, currency: "MVR",
                          reference: "order-2", card_reference: "cof_1")

      expect(
        a_request(:post, "#{sandbox_base}/transactions") do |req|
          body = JSON.parse(req.body)
          body.keys.sort == %w[amount card_reference currency customer_id reference] && !body.key?("return_url")
        end
      ).to have_been_made
    end

    it "maps a 201 redirect response to a pending Transaction with a payment_url" do
      stub_request(:post, "#{sandbox_base}/transactions").to_return(status: 201, body: redirect_response.to_json)

      txn = transactions.create(customer_id: "cus_1", amount: 15_000, currency: "MVR",
                                reference: "order-1", return_url: "https://merchant.example/return")

      expect(txn.status).to eq("pending")
      expect(txn.payment_url).to eq("https://connect.bml.example/pay/txn_1")
    end

    it "normalizes a 409 replay carrying the identical existing record to an idempotent success" do
      stub_request(:post, "#{sandbox_base}/transactions").to_return(status: 409, body: redirect_response.to_json)

      txn = transactions.create(customer_id: "cus_1", amount: 15_000, currency: "MVR",
                                reference: "order-1", return_url: "https://merchant.example/return")

      expect(txn.id).to eq("txn_1")
    end

    it "raises a conflict for a 409 whose existing record differs in a material parameter" do
      stub_request(:post, "#{sandbox_base}/transactions")
        .to_return(status: 409, body: redirect_response.merge(amount: 1).to_json)

      expect do
        transactions.create(customer_id: "cus_1", amount: 15_000, currency: "MVR",
                            reference: "order-1", return_url: "https://merchant.example/return")
      end.to raise_error(BmlTokenization::ConflictError)
    end

    it "maps 400->validation(field), 404->not-found, 401->auth" do
      stub_request(:post, "#{sandbox_base}/transactions").to_return(status: 400, body: { field: "amount" }.to_json)
      expect do
        transactions.create(customer_id: "c", amount: 15_000, currency: "MVR", reference: "r1",
                            return_url: "https://m.example/r")
      end.to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:amount) }

      stub_request(:post, "#{sandbox_base}/transactions").to_return(status: 404, body: "{}")
      expect do
        transactions.create(customer_id: "nope", amount: 15_000, currency: "MVR", reference: "r2",
                            return_url: "https://m.example/r")
      end.to raise_error(BmlTokenization::NotFoundError)

      stub_request(:post, "#{sandbox_base}/transactions").to_return(status: 401, body: "{}")
      expect do
        transactions.create(customer_id: "c", amount: 15_000, currency: "MVR", reference: "r3",
                            return_url: "https://m.example/r")
      end.to raise_error(BmlTokenization::AuthenticationError)
    end
  end

  describe "retrieve — GET /transactions/{id}" do
    it "maps 200->Transaction(normalized status), 404->not-found, 403->auth" do
      stub_request(:get, "#{sandbox_base}/transactions/txn_1").to_return(status: 200, body: redirect_response.to_json)
      expect(transactions.retrieve("txn_1").status).to eq("pending")

      stub_request(:get, "#{sandbox_base}/transactions/missing").to_return(status: 404, body: "{}")
      expect { transactions.retrieve("missing") }.to raise_error(BmlTokenization::NotFoundError)

      stub_request(:get, "#{sandbox_base}/transactions/txn_1").to_return(status: 403, body: "{}")
      expect { transactions.retrieve("txn_1") }.to raise_error(BmlTokenization::AuthenticationError)
    end
  end

  describe "list — GET /transactions" do
    it "sends page-number pagination plus optional filters and never an over-max page_size" do
      stub_request(:get, "#{sandbox_base}/transactions")
        .with(query: { page: 2, page_size: 50, customer_id: "cus_1", status: "succeeded" })
        .to_return(status: 200, body: { records: [], page: 2, page_size: 50 }.to_json)

      transactions.list(page: 2, page_size: 50, customer_id: "cus_1", status: "succeeded")

      expect(
        a_request(:get, "#{sandbox_base}/transactions")
          .with(query: { page: 2, page_size: 50, customer_id: "cus_1", status: "succeeded" })
      ).to have_been_made
    end

    it "omits absent filters from the query" do
      stub_request(:get, "#{sandbox_base}/transactions").with(query: { page: 1, page_size: 20 })
                                                        .to_return(status: 200, body: { records: [] }.to_json)

      transactions.list

      # Exact query match: only page + page_size are sent; nil customer_id /
      # status filters are dropped before the request.
      expect(
        a_request(:get, "#{sandbox_base}/transactions").with(query: { page: 1, page_size: 20 })
      ).to have_been_made
    end

    it "maps a 200 with zero records to an empty page (not an error)" do
      stub_request(:get, "#{sandbox_base}/transactions").with(query: { page: 1, page_size: 20 })
                                                        .to_return(status: 200, body: { records: [] }.to_json)

      expect(transactions.list).to be_empty
    end
  end

  describe "environment isolation (FR-007, SC-006)" do
    it "routes a sandbox client to the sandbox base URL and never to production" do
      stub_request(:get, "#{sandbox_base}/transactions/txn_1").to_return(status: 200, body: redirect_response.to_json)

      BmlTokenization::Client.new(api_key: "k", environment: :sandbox, retry_backoff: 0)
                             .transactions.retrieve("txn_1")

      expect(a_request(:get, "#{sandbox_base}/transactions/txn_1")).to have_been_made
      expect(a_request(:any, %r{//api\.merchants\.bankofmaldives})).not_to have_been_made
    end

    it "routes a production client to the production base URL and never to sandbox" do
      stub_request(:get, "#{production_base}/transactions/txn_1").to_return(status: 200,
                                                                            body: redirect_response.to_json)

      BmlTokenization::Client.new(api_key: "k", environment: :production, retry_backoff: 0)
                             .transactions.retrieve("txn_1")

      expect(a_request(:get, "#{production_base}/transactions/txn_1")).to have_been_made
      expect(a_request(:any, /api\.uat\./)).not_to have_been_made
    end
  end

  describe "resilience (timeout, bounded retry, rate-limit) (R2)" do
    it "retries a transient 5xx then succeeds within the bounded budget" do
      stub_request(:get, "#{sandbox_base}/transactions/txn_1")
        .to_return({ status: 503, body: "{}" }, { status: 503, body: "{}" },
                   { status: 200, body: redirect_response.to_json })

      expect(transactions.retrieve("txn_1").id).to eq("txn_1")
      expect(a_request(:get, "#{sandbox_base}/transactions/txn_1")).to have_been_made.times(3)
    end

    it "raises a distinguishable availability error after retries are exhausted, with no partial record" do
      stub_request(:get, "#{sandbox_base}/transactions/txn_1").to_return(status: 503, body: "{}")

      result = nil
      expect { result = transactions.retrieve("txn_1") }.to raise_error(BmlTokenization::AvailabilityError)
      expect(result).to be_nil
    end

    it "retries a 429 honouring Retry-After then succeeds" do
      stub_request(:get, "#{sandbox_base}/transactions/txn_1")
        .to_return({ status: 429, headers: { "Retry-After" => "0" }, body: "{}" },
                   { status: 200, body: redirect_response.to_json })

      expect(transactions.retrieve("txn_1").id).to eq("txn_1")
    end

    it "does not retry a non-transient 404" do
      stub_request(:get, "#{sandbox_base}/transactions/missing").to_return(status: 404, body: "{}")

      expect { transactions.retrieve("missing") }.to raise_error(BmlTokenization::NotFoundError)
      expect(a_request(:get, "#{sandbox_base}/transactions/missing")).to have_been_made.times(1)
    end
  end
end
