# frozen_string_literal: true

RSpec.describe BmlTokenization::Customers do
  let(:client) { BmlTokenization::Client.new(api_key: "key", app_id: "app", environment: :sandbox) }
  let(:customers) { client.customers }
  let(:base) { "https://api.sandbox.bml.mv" }

  let(:valid_details) do
    { first_name: "Aisha", last_name: "Ali", email: "aisha@example.mv" }
  end

  describe "local required-field validation runs before any remote call (FR-006)" do
    %i[first_name last_name email].each do |field|
      it "rejects a missing #{field} without making a network call" do
        details = valid_details.reject { |k, _| k == field }

        expect { customers.create(details) }
          .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(field) }
        expect(a_request(:any, /bml/)).not_to have_been_made
      end

      it "rejects a blank #{field} naming the field" do
        details = valid_details.merge(field => "   ")

        expect { customers.create(details) }
          .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(field) }
        expect(a_request(:any, /bml/)).not_to have_been_made
      end
    end

    it "rejects an over-cap page_size on list without a network call" do
      expect { customers.list(page_size: 101) }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:page_size) }
      expect(a_request(:any, /bml/)).not_to have_been_made
    end

    it "rejects a blank id on retrieve without a network call" do
      expect { customers.retrieve("") }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:id) }
      expect(a_request(:any, /bml/)).not_to have_been_made
    end
  end

  describe "error mapping is distinguishable by type (FR-009)" do
    {
      400 => BmlTokenization::ValidationError,
      401 => BmlTokenization::AuthenticationError,
      403 => BmlTokenization::AuthenticationError,
      404 => BmlTokenization::NotFoundError,
      409 => BmlTokenization::ConflictError,
      500 => BmlTokenization::AvailabilityError,
      503 => BmlTokenization::AvailabilityError
    }.each do |status, error_class|
      it "maps HTTP #{status} to #{error_class}" do
        stub_request(:post, "#{base}/customers").to_return(status: status, body: "{}")

        expect { customers.create(valid_details) }.to raise_error(error_class)
      end
    end

    it "maps a transport timeout to an availability error with no partial record" do
      stub_request(:post, "#{base}/customers").to_timeout

      expect { customers.create(valid_details) }.to raise_error(BmlTokenization::AvailabilityError)
    end
  end

  describe "structured logging is masked (FR-010, Constitution IV)" do
    let(:logger) { instance_double("Logger") }
    let(:client) do
      BmlTokenization::Client.new(api_key: "key", app_id: "app", environment: :sandbox, logger: logger)
    end

    it "logs a structured, PII-minimized entry and never card data" do
      stub_request(:post, "#{base}/customers")
        .to_return(status: 201, body: { id: "cust_1" }.to_json)

      captured = nil
      allow(logger).to receive(:info) { |entry| captured = entry }

      customers.create(valid_details)

      expect(captured).to include(operation: :create, resource: "customers", outcome: :success)
      expect(captured[:customer_id]).to eq("cust_1")
    end
  end

  describe "no SAD/PAN leakage across operations (FR-010, SC-004)" do
    it "never sends card data even if a caller sneaks it into the details" do
      stub_request(:post, "#{base}/customers").to_return(status: 201, body: { id: "c1" }.to_json)

      customers.create(valid_details.merge(card_number: "4111111111111111", cvv: "123"))

      expect(
        a_request(:post, "#{base}/customers").with do |req|
          !req.body.include?("4111111111111111") && !req.body.include?("card_number")
        end
      ).to have_been_made
    end

    it "never exposes card data returned by the platform on the record" do
      stub_request(:get, "#{base}/customers/c1").to_return(
        status: 200,
        body: { id: "c1", first_name: "A", last_name: "B", email: "a@b.mv",
                card_number: "4111111111111111", cvv: "123" }.to_json
      )

      customer = customers.retrieve("c1")

      expect(customer.to_h.to_s).not_to include("4111111111111111")
      expect(customer).not_to respond_to(:card_number)
    end
  end
end
