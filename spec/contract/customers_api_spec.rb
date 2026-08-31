# frozen_string_literal: true

# Verifies the public library API contract (contracts/library-api.md): the
# accessor, and each operation's inputs, outputs, and error conditions.
RSpec.describe "Customers public API contract" do
  let(:client) { BmlTokenization::Client.new(api_key: "key", app_id: "app", environment: :sandbox) }
  let(:base) { "https://api.sandbox.bml.mv" }

  let(:valid_details) do
    { first_name: "Aisha", last_name: "Ali", email: "aisha@example.mv", phone: "+9607777777", reference: "acct-42" }
  end

  it "exposes client.customers (FR-001)" do
    expect(client.customers).to be_a(BmlTokenization::Customers)
    expect(client.customers).to be(client.customers) # memoized, same resource
  end

  describe "create (FR-002)" do
    it "returns a Customer with the platform id plus submitted details" do
      stub_request(:post, "#{base}/customers").to_return(
        status: 201,
        body: valid_details.merge(id: "cust_1").to_json,
        headers: { "Content-Type" => "application/json" }
      )

      customer = client.customers.create(valid_details)

      expect(customer).to be_a(BmlTokenization::Customer)
      expect(customer.id).to eq("cust_1")
      expect(customer.first_name).to eq("Aisha")
      expect(customer.email).to eq("aisha@example.mv")
    end

    it "raises a validation error naming the field with NO network call on missing required input (SC-003)" do
      expect { client.customers.create(valid_details.reject { |k, _| k == :email }) }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:email) }
      expect(a_request(:any, /bml/)).not_to have_been_made
    end
  end

  describe "retrieve (FR-003)" do
    it "returns the current Customer" do
      stub_request(:get, "#{base}/customers/cust_1")
        .to_return(status: 200, body: { id: "cust_1", first_name: "Aisha" }.to_json)

      customer = client.customers.retrieve("cust_1")
      expect(customer.id).to eq("cust_1")
    end

    it "raises not-found for an unknown identifier (US2-2)" do
      stub_request(:get, "#{base}/customers/missing").to_return(status: 404, body: "{}")

      expect { client.customers.retrieve("missing") }.to raise_error(BmlTokenization::NotFoundError)
    end
  end

  describe "list (FR-004)" do
    it "returns a CustomerListPage and defaults page_size to 20" do
      stub_request(:get, "#{base}/customers").with(query: { page: 1, page_size: 20 })
                                             .to_return(status: 200, body: { data: [{ id: "c1" }], page: 1,
                                                                             page_size: 20, has_next: false }.to_json)

      page = client.customers.list

      expect(page).to be_a(BmlTokenization::CustomerListPage)
      expect(page.page_size).to eq(20)
      expect(page.records.map(&:id)).to eq(["c1"])
    end

    it "rejects page_size > 100 naming page_size with NO network call (FR-006)" do
      expect { client.customers.list(page_size: 101) }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:page_size) }
      expect(a_request(:any, /bml/)).not_to have_been_made
    end

    it "returns an empty page (not an error) when there are no results" do
      stub_request(:get, "#{base}/customers").with(query: { page: 1, page_size: 20 })
                                             .to_return(status: 200, body: { data: [], page: 1, page_size: 20,
                                                                             has_next: false }.to_json)

      page = client.customers.list
      expect(page).to be_empty
    end
  end

  describe "update — full replace (FR-005)" do
    it "sends the complete record and returns the updated Customer" do
      stub_request(:put, "#{base}/customers/cust_1")
        .to_return(status: 200, body: valid_details.merge(id: "cust_1").to_json)

      customer = client.customers.update("cust_1", valid_details)
      expect(customer.id).to eq("cust_1")
    end

    it "clears mutable fields omitted from the record (full-replace)" do
      stub_request(:put, "#{base}/customers/cust_1").to_return(status: 200, body: { id: "cust_1" }.to_json)

      client.customers.update("cust_1", { first_name: "A", last_name: "B", email: "a@b.mv" })

      expect(
        a_request(:put, "#{base}/customers/cust_1").with do |req|
          body = JSON.parse(req.body)
          body.key?("phone") && body["phone"].nil? && body.key?("reference") && body["reference"].nil?
        end
      ).to have_been_made
    end

    it "raises a validation error naming the field with NO network call and customer unchanged (US4-2)" do
      expect { client.customers.update("cust_1", { first_name: "A", last_name: "B" }) }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:email) }
      expect(a_request(:any, /bml/)).not_to have_been_made
    end

    it "raises not-found for an unknown identifier" do
      stub_request(:put, "#{base}/customers/missing").to_return(status: 404, body: "{}")

      expect { client.customers.update("missing", valid_details) }.to raise_error(BmlTokenization::NotFoundError)
    end
  end
end
