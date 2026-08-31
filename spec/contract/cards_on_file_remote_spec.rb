# frozen_string_literal: true

# Verifies conformance to the remote BML HTTP contract (contracts/bml-remote.md)
# using WebMock stubs — no live credentials required. Covers request shape, the
# response->library mapping, idempotent re-store, environment isolation, and the
# transient-failure / rate-limit resilience behaviour (FR-014).
RSpec.describe "CardsOnFile remote HTTP contract" do
  let(:sandbox_base) { BmlTokenization::Client::BASE_URLS[:sandbox] }
  let(:production_base) { BmlTokenization::Client::BASE_URLS[:production] }
  let(:client) do
    BmlTokenization::Client.new(api_key: "key", app_id: "app", environment: :sandbox, retry_backoff: 0)
  end
  let(:cards) { client.cards_on_file }
  let(:card_json) do
    { reference: "card_ref_1", customer_id: "cust_1", scheme: "visa", last_four: "4242",
      expiry_month: 12, expiry_year: 2030, status: "active" }
  end

  describe "store endpoint" do
    it "sends only customer_id + card_handle (no PAN/CVV/SAD) with auth headers" do
      stub_request(:post, "#{sandbox_base}/cards-on-file").to_return(status: 201, body: card_json.to_json)

      cards.store(customer_id: "cust_1", card_handle: "tok_handle")

      expect(
        a_request(:post, "#{sandbox_base}/cards-on-file")
          .with(headers: { "Authorization" => "Bearer key", "X-App-Id" => "app" }) do |req|
            body = JSON.parse(req.body)
            body.keys.sort == %w[card_handle customer_id] &&
              %w[pan card_number cvv cvv2 pin track track1 track2].none? { |k| body.key?(k) } &&
              !req.body.match?(/\b(?:\d[ -]?){12,19}\b/)
          end
      ).to have_been_made
    end

    it "maps a 2xx card response to a CardOnFile with only masked data (no full PAN)" do
      stub_request(:post, "#{sandbox_base}/cards-on-file")
        .to_return(status: 200, body: card_json.merge(card_number: "4242424242424242").to_json)

      card = cards.store(customer_id: "cust_1", card_handle: "tok_handle")

      expect(card.last_four).to eq("4242")
      expect(card.to_h.to_s).not_to include("4242424242424242")
      expect(card).not_to respond_to(:card_number)
    end

    it "normalizes an already-on-file 409 carrying the existing reference to an idempotent success" do
      stub_request(:post, "#{sandbox_base}/cards-on-file")
        .to_return(status: 409, body: card_json.to_json)

      card = cards.store(customer_id: "cust_1", card_handle: "tok_handle")

      expect(card.reference).to eq("card_ref_1")
    end

    it "raises a conflict error for a genuine conflict that carries no existing reference" do
      stub_request(:post, "#{sandbox_base}/cards-on-file")
        .to_return(status: 409, body: { error: "conflict" }.to_json)

      expect { cards.store(customer_id: "cust_1", card_handle: "tok_handle") }
        .to raise_error(BmlTokenization::ConflictError)
    end

    it "maps invalid handle->validation, unknown customer->not-found, auth->auth" do
      stub_request(:post, "#{sandbox_base}/cards-on-file").to_return(status: 422,
                                                                     body: { field: "card_handle" }.to_json)
      expect { cards.store(customer_id: "cust_1", card_handle: "bad") }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:card_handle) }

      stub_request(:post, "#{sandbox_base}/cards-on-file").to_return(status: 404, body: "{}")
      expect { cards.store(customer_id: "nope", card_handle: "tok") }
        .to raise_error(BmlTokenization::NotFoundError)

      stub_request(:post, "#{sandbox_base}/cards-on-file").to_return(status: 401, body: "{}")
      expect { cards.store(customer_id: "cust_1", card_handle: "tok") }
        .to raise_error(BmlTokenization::AuthenticationError)
    end
  end

  describe "list endpoint" do
    it "sends the customer filter and no pagination params" do
      stub_request(:get, "#{sandbox_base}/cards-on-file").with(query: { customer_id: "cust_1" })
                                                         .to_return(status: 200, body: { data: [] }.to_json)

      cards.list(customer_id: "cust_1")

      expect(
        a_request(:get, "#{sandbox_base}/cards-on-file").with(query: { customer_id: "cust_1" }) do |req|
          uri = URI(req.uri.to_s)
          params = URI.decode_www_form(uri.query.to_s).to_h
          params.keys == ["customer_id"] # no page / page_size
        end
      ).to have_been_made
    end

    it "maps an empty data array to an empty CardOnFileList" do
      stub_request(:get, "#{sandbox_base}/cards-on-file").with(query: { customer_id: "cust_1" })
                                                         .to_return(status: 200, body: { data: [] }.to_json)

      expect(cards.list(customer_id: "cust_1")).to be_empty
    end
  end

  describe "retrieve endpoint" do
    it "maps 404->not-found and auth failure->auth, and carries only masked data" do
      stub_request(:get, "#{sandbox_base}/cards-on-file/missing").to_return(status: 404, body: "{}")
      expect { cards.retrieve("missing") }.to raise_error(BmlTokenization::NotFoundError)

      stub_request(:get, "#{sandbox_base}/cards-on-file/card_ref_1").to_return(status: 403, body: "{}")
      expect { cards.retrieve("card_ref_1") }.to raise_error(BmlTokenization::AuthenticationError)

      stub_request(:get, "#{sandbox_base}/cards-on-file/card_ref_1")
        .to_return(status: 200, body: card_json.to_json)
      expect(cards.retrieve("card_ref_1").to_h.to_s).not_to match(/\b(?:\d[ -]?){12,19}\b/)
    end
  end

  describe "remove endpoint" do
    it "issues a DELETE and maps unknown/already-removed (404)->not-found, auth->auth" do
      stub_request(:delete, "#{sandbox_base}/cards-on-file/card_ref_1").to_return(status: 200, body: "{}")
      cards.remove("card_ref_1")
      expect(a_request(:delete, "#{sandbox_base}/cards-on-file/card_ref_1")).to have_been_made

      stub_request(:delete, "#{sandbox_base}/cards-on-file/gone").to_return(status: 404, body: "{}")
      expect { cards.remove("gone") }.to raise_error(BmlTokenization::NotFoundError)

      stub_request(:delete, "#{sandbox_base}/cards-on-file/x").to_return(status: 401, body: "{}")
      expect { cards.remove("x") }.to raise_error(BmlTokenization::AuthenticationError)
    end
  end

  # T035 — environment isolation (FR-008, SC-005)
  describe "environment isolation" do
    it "routes a sandbox client to the sandbox base URL and never to production" do
      stub_request(:get, "#{sandbox_base}/cards-on-file/card_ref_1").to_return(status: 200, body: card_json.to_json)

      BmlTokenization::Client.new(api_key: "k", environment: :sandbox, retry_backoff: 0)
                             .cards_on_file.retrieve("card_ref_1")

      expect(a_request(:get, "#{sandbox_base}/cards-on-file/card_ref_1")).to have_been_made
      expect(a_request(:any, %r{//api\.merchants\.bankofmaldives})).not_to have_been_made
    end

    it "routes a production client to the production base URL and never to sandbox" do
      stub_request(:get, "#{production_base}/cards-on-file/card_ref_1").to_return(status: 200, body: card_json.to_json)

      BmlTokenization::Client.new(api_key: "k", environment: :production, retry_backoff: 0)
                             .cards_on_file.retrieve("card_ref_1")

      expect(a_request(:get, "#{production_base}/cards-on-file/card_ref_1")).to have_been_made
      expect(a_request(:any, /api\.uat\./)).not_to have_been_made
    end
  end

  # T036 — resilience: transient retry, retry-exhausted availability, 429 rate-limit (FR-014)
  describe "resilience (timeout, bounded retry, rate-limit)" do
    it "retries a transient 5xx and then succeeds within the bounded budget" do
      stub_request(:get, "#{sandbox_base}/cards-on-file/card_ref_1")
        .to_return({ status: 503, body: "{}" }, { status: 503, body: "{}" },
                   { status: 200, body: card_json.to_json })

      card = cards.retrieve("card_ref_1")

      expect(card.reference).to eq("card_ref_1")
      expect(a_request(:get, "#{sandbox_base}/cards-on-file/card_ref_1")).to have_been_made.times(3)
    end

    it "retries a transport timeout then succeeds" do
      stub_request(:get, "#{sandbox_base}/cards-on-file/card_ref_1")
        .to_timeout.then.to_return(status: 200, body: card_json.to_json)

      expect(cards.retrieve("card_ref_1").reference).to eq("card_ref_1")
    end

    it "raises a distinguishable availability error after retries are exhausted, with no partial record" do
      stub_request(:get, "#{sandbox_base}/cards-on-file/card_ref_1").to_return(status: 503, body: "{}")

      result = nil
      expect { result = cards.retrieve("card_ref_1") }.to raise_error(BmlTokenization::AvailabilityError)
      expect(result).to be_nil
      expect(a_request(:get, "#{sandbox_base}/cards-on-file/card_ref_1")).to have_been_made.times(3)
    end

    it "retries a 429 honouring Retry-After then succeeds" do
      stub_request(:get, "#{sandbox_base}/cards-on-file/card_ref_1")
        .to_return({ status: 429, headers: { "Retry-After" => "0" }, body: "{}" },
                   { status: 200, body: card_json.to_json })

      expect(cards.retrieve("card_ref_1").reference).to eq("card_ref_1")
    end

    it "raises a distinguishable rate-limit error when still limited after retries" do
      stub_request(:get, "#{sandbox_base}/cards-on-file/card_ref_1")
        .to_return(status: 429, headers: { "Retry-After" => "0" }, body: "{}")

      expect { cards.retrieve("card_ref_1") }.to raise_error(BmlTokenization::RateLimitError)
      expect(a_request(:get, "#{sandbox_base}/cards-on-file/card_ref_1")).to have_been_made.times(3)
    end

    it "does not retry a non-transient error (404 fails on the first attempt)" do
      stub_request(:get, "#{sandbox_base}/cards-on-file/missing").to_return(status: 404, body: "{}")

      expect { cards.retrieve("missing") }.to raise_error(BmlTokenization::NotFoundError)
      expect(a_request(:get, "#{sandbox_base}/cards-on-file/missing")).to have_been_made.times(1)
    end
  end
end
