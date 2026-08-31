# frozen_string_literal: true

# Verifies conformance to the remote BML HTTP contract (contracts/bml-remote.md)
# using WebMock stubs — no live credentials required.
RSpec.describe "Customers remote HTTP contract" do
  let(:client) { BmlTokenization::Client.new(api_key: "key", app_id: "app", environment: :sandbox) }
  let(:base) { "https://api.sandbox.bml.mv" }
  let(:details) do
    { first_name: "Aisha", last_name: "Ali", email: "aisha@example.mv", phone: "+9607777777", reference: "acct-42" }
  end

  describe "create endpoint" do
    it "sends the customer fields, auth headers, and never any card data (FR-010)" do
      stub_request(:post, "#{base}/customers").to_return(status: 201, body: { id: "c1" }.to_json)

      client.customers.create(details)

      expect(
        a_request(:post, "#{base}/customers")
          .with(headers: { "Authorization" => "Bearer key", "X-App-Id" => "app" }) do |req|
            body = JSON.parse(req.body)
            body.values_at("first_name", "last_name", "email", "phone", "reference") ==
              ["Aisha", "Ali", "aisha@example.mv", "+9607777777", "acct-42"] &&
              %w[card_number pan cvv cvv2 pin track track1 track2].none? { |k| body.key?(k) } &&
              !req.body.match?(/\b(?:\d[ -]?){12,19}\b/)
          end
      ).to have_been_made
    end

    it "maps duplicate → conflict, auth → auth, timeout/5xx → availability" do
      stub_request(:post, "#{base}/customers").to_return(status: 409, body: "{}")
      expect { client.customers.create(details) }.to raise_error(BmlTokenization::ConflictError)

      stub_request(:post, "#{base}/customers").to_return(status: 401, body: "{}")
      expect { client.customers.create(details) }.to raise_error(BmlTokenization::AuthenticationError)

      stub_request(:post, "#{base}/customers").to_return(status: 503, body: "{}")
      expect { client.customers.create(details) }.to raise_error(BmlTokenization::AvailabilityError)
    end
  end

  describe "get endpoint" do
    it "maps 404 → not-found and auth failure → auth" do
      stub_request(:get, "#{base}/customers/missing").to_return(status: 404, body: "{}")
      expect { client.customers.retrieve("missing") }.to raise_error(BmlTokenization::NotFoundError)

      stub_request(:get, "#{base}/customers/c1").to_return(status: 403, body: "{}")
      expect { client.customers.retrieve("c1") }.to raise_error(BmlTokenization::AuthenticationError)
    end
  end

  describe "list endpoint" do
    it "sends page-number params" do
      stub_request(:get, "#{base}/customers").with(query: { page: 2, page_size: 50 })
                                             .to_return(status: 200, body: { data: [], page: 2, page_size: 50,
                                                                             has_next: false }.to_json)

      client.customers.list(page: 2, page_size: 50)

      expect(a_request(:get, "#{base}/customers").with(query: { page: 2, page_size: 50 })).to have_been_made
    end

    it "yields an empty page for an empty data array" do
      stub_request(:get, "#{base}/customers").with(query: { page: 1, page_size: 20 })
                                             .to_return(status: 200, body: { data: [], has_next: false }.to_json)

      expect(client.customers.list).to be_empty
    end
  end

  describe "update endpoint" do
    it "sends the complete record and maps 404 → not-found, invalid field → validation" do
      stub_request(:put, "#{base}/customers/c1").to_return(status: 200, body: { id: "c1" }.to_json)
      client.customers.update("c1", details)
      expect(
        a_request(:put, "#{base}/customers/c1").with do |req|
          body = JSON.parse(req.body)
          %w[first_name last_name email phone reference].all? { |k| body.key?(k) }
        end
      ).to have_been_made

      stub_request(:put, "#{base}/customers/missing").to_return(status: 404, body: "{}")
      expect { client.customers.update("missing", details) }.to raise_error(BmlTokenization::NotFoundError)

      stub_request(:put, "#{base}/customers/c1").to_return(status: 422, body: { field: "email" }.to_json)
      expect { client.customers.update("c1", details) }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:email) }
    end
  end

  describe "environment isolation (FR-007, SC-005)" do
    it "routes to the sandbox base URL and never to production" do
      stub_request(:get, "https://api.sandbox.bml.mv/customers/c1").to_return(status: 200, body: { id: "c1" }.to_json)

      BmlTokenization::Client.new(api_key: "k", environment: :sandbox).customers.retrieve("c1")

      expect(a_request(:get, "https://api.sandbox.bml.mv/customers/c1")).to have_been_made
      expect(a_request(:any, /api\.bml\.mv/)).not_to have_been_made
    end

    it "routes to the production base URL and never to sandbox" do
      stub_request(:get, "https://api.bml.mv/customers/c1").to_return(status: 200, body: { id: "c1" }.to_json)

      BmlTokenization::Client.new(api_key: "k", environment: :production).customers.retrieve("c1")

      expect(a_request(:get, "https://api.bml.mv/customers/c1")).to have_been_made
      expect(a_request(:any, /sandbox/)).not_to have_been_made
    end
  end

  describe "auth/config and availability mapping (FR-008, FR-009)" do
    it "distinguishes auth/config from availability, returning no partial record on timeout" do
      stub_request(:get, "#{base}/customers/c1").to_return(status: 401, body: "{}")
      expect { client.customers.retrieve("c1") }.to raise_error(BmlTokenization::AuthenticationError)

      stub_request(:get, "#{base}/customers/c2").to_timeout
      result = nil
      expect { result = client.customers.retrieve("c2") }.to raise_error(BmlTokenization::AvailabilityError)
      expect(result).to be_nil
    end

    it "refuses to send over a non-TLS base URL (config error)" do
      insecure = BmlTokenization::Client.new(api_key: "k", base_url: "http://insecure.bml.mv")
      expect { insecure.customers.retrieve("c1") }.to raise_error(BmlTokenization::ConfigurationError)
      expect(a_request(:any, /insecure/)).not_to have_been_made
    end
  end
end
