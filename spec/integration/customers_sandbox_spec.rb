# frozen_string_literal: true

# Opt-in, credential-gated end-to-end suite against the real BML sandbox
# (FR-011). Skips cleanly when credentials are absent so the deterministic
# suite stays runnable without secrets. These specs make REAL network calls,
# so they enable Net::HTTP connections only within this file.
RSpec.describe "Customers sandbox integration", :integration do
  before(:all) do
    @credentials_present = ENV["BML_API_KEY"] && !ENV["BML_API_KEY"].empty?
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

  let(:details) do
    unique = "#{Process.pid}-#{caller.object_id}"
    {
      first_name: "Test",
      last_name: "Customer",
      email: "test+#{unique}@example.mv",
      phone: "+9607777777",
      reference: "it-#{unique}"
    }
  end

  before do
    skip "Set BML_API_KEY (and BML_APP_ID) to run the sandbox integration suite" unless @credentials_present
  end

  it "creates a customer end-to-end in the sandbox environment (US1-3, SC-005)" do
    customer = client.customers.create(details)

    expect(customer).to be_a(BmlTokenization::Customer)
    expect(customer.id).not_to be_nil
    expect(client.environment).to eq(:sandbox)
    expect(client.base_url).to include("sandbox")
  end

  it "creates then retrieves the same customer (round-trip)" do
    created = client.customers.create(details)
    fetched = client.customers.retrieve(created.id)

    expect(fetched.id).to eq(created.id)
    expect(fetched.email).to eq(details[:email])
  end

  it "lists customers with pagination (US3-2)" do
    client.customers.create(details)

    page = client.customers.list(page: 1, page_size: 20)

    expect(page).to be_a(BmlTokenization::CustomerListPage)
    expect(page.page_size).to eq(20)
  end

  it "updates a customer with full-replace semantics (US4-1)" do
    created = client.customers.create(details)

    updated = client.customers.update(
      created.id,
      details.merge(first_name: "Updated")
    )
    refetched = client.customers.retrieve(created.id)

    expect(updated.first_name).to eq("Updated")
    expect(refetched.first_name).to eq("Updated")
  end
end
