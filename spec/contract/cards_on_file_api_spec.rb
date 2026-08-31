# frozen_string_literal: true

# Verifies the public library API contract for the CardsOnFile resource
# (contracts/library-api.md): inputs, outputs, and error conditions for
# store / list / retrieve / remove, plus audit emission on state changes.
RSpec.describe "CardsOnFile public API contract" do
  let(:base) { BmlTokenization::Client::BASE_URLS[:sandbox] }
  let(:audit_sink) { [] }
  let(:client) do
    BmlTokenization::Client.new(
      api_key: "key", app_id: "app", environment: :sandbox, retry_backoff: 0, audit_sink: audit_sink
    )
  end
  let(:cards) { client.cards_on_file }

  let(:card_json) do
    {
      reference: "card_ref_1", customer_id: "cust_1", scheme: "visa",
      last_four: "4242", expiry_month: 12, expiry_year: 2030, status: "active"
    }
  end

  it "is reachable via the client accessor (FR-001)" do
    expect(client.cards_on_file).to be_a(BmlTokenization::CardsOnFile)
  end

  describe "store (FR-002, FR-003, FR-013, FR-015)" do
    it "returns a CardOnFile with a safe reference + masked summary and no full card number" do
      stub_request(:post, "#{base}/cards-on-file").to_return(status: 201, body: card_json.to_json)

      card = cards.store(customer_id: "cust_1", card_handle: "tok_handle")

      expect(card).to be_a(BmlTokenization::CardOnFile)
      expect(card.reference).to eq("card_ref_1")
      expect(card.last_four).to eq("4242")
      expect(card).not_to respond_to(:card_number)
      expect(card.to_h.to_s).not_to match(/\b(?:\d[ -]?){12,19}\b/)
    end

    %i[customer_id card_handle].each do |field|
      it "raises a validation error naming a missing #{field} with NO network call (FR-007, SC-006)" do
        args = { customer_id: "cust_1", card_handle: "tok_handle" }.merge(field => nil)

        expect { cards.store(**args) }
          .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(field) }
        expect(a_request(:any, /cards-on-file/)).not_to have_been_made
      end

      it "raises a validation error naming a blank #{field} with NO network call" do
        args = { customer_id: "cust_1", card_handle: "tok_handle" }.merge(field => "   ")

        expect { cards.store(**args) }
          .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(field) }
        expect(a_request(:any, /cards-on-file/)).not_to have_been_made
      end
    end

    it "returns the existing record (no duplicate) when the card is already on file (FR-013)" do
      stub_request(:post, "#{base}/cards-on-file")
        .to_return(status: 409, body: card_json.to_json)

      card = cards.store(customer_id: "cust_1", card_handle: "tok_handle")

      expect(card).to be_a(BmlTokenization::CardOnFile)
      expect(card.reference).to eq("card_ref_1")
    end

    it "emits a store audit record with no card data (FR-015)" do
      stub_request(:post, "#{base}/cards-on-file").to_return(status: 201, body: card_json.to_json)

      cards.store(customer_id: "cust_1", card_handle: "tok_handle", actor: "user-9")

      expect(audit_sink.size).to eq(1)
      record = audit_sink.first
      expect(record.action).to eq("store")
      expect(record.card_reference).to eq("card_ref_1")
      expect(record.actor).to include("user-9")
      expect(record.to_h.to_s).not_to include("tok_handle")
    end
  end

  describe "list (FR-004, US2-2, FR-015)" do
    it "returns a CardOnFileList of the customer's cards with safe reference + masked summary" do
      stub_request(:get, "#{base}/cards-on-file").with(query: { customer_id: "cust_1" })
                                                 .to_return(status: 200, body: { data: [card_json] }.to_json)

      list = cards.list(customer_id: "cust_1")

      expect(list).to be_a(BmlTokenization::CardOnFileList)
      expect(list.size).to eq(1)
      expect(list.first.reference).to eq("card_ref_1")
    end

    it "yields an empty list (not an error) for a customer with no cards" do
      stub_request(:get, "#{base}/cards-on-file").with(query: { customer_id: "cust_1" })
                                                 .to_return(status: 200, body: { data: [] }.to_json)

      expect(cards.list(customer_id: "cust_1")).to be_empty
    end

    it "emits NO audit record" do
      stub_request(:get, "#{base}/cards-on-file").with(query: { customer_id: "cust_1" })
                                                 .to_return(status: 200, body: { data: [] }.to_json)

      cards.list(customer_id: "cust_1")

      expect(audit_sink).to be_empty
    end
  end

  describe "retrieve (FR-005, US3-2, FR-015)" do
    it "returns the current CardOnFile with masked summary and discoverable expiry/validity" do
      stub_request(:get, "#{base}/cards-on-file/card_ref_1")
        .to_return(status: 200, body: card_json.to_json)

      card = cards.retrieve("card_ref_1")

      expect(card.reference).to eq("card_ref_1")
      expect(card.expiry_month).to eq(12)
      expect(card.expired?).to be(false)
    end

    it "raises a not-found error for an unknown reference (US3-2)" do
      stub_request(:get, "#{base}/cards-on-file/missing").to_return(status: 404, body: "{}")

      expect { cards.retrieve("missing") }.to raise_error(BmlTokenization::NotFoundError)
    end

    it "emits NO audit record" do
      stub_request(:get, "#{base}/cards-on-file/card_ref_1")
        .to_return(status: 200, body: card_json.to_json)

      cards.retrieve("card_ref_1")

      expect(audit_sink).to be_empty
    end
  end

  describe "remove (FR-006, FR-006a, US4-1, US4-2, FR-015)" do
    it "permanently deletes the card so it is not-found afterward and absent from the list (SC-004)" do
      stub_request(:delete, "#{base}/cards-on-file/card_ref_1").to_return(status: 200, body: "{}")
      stub_request(:get, "#{base}/cards-on-file/card_ref_1").to_return(status: 404, body: "{}")
      stub_request(:get, "#{base}/cards-on-file").with(query: { customer_id: "cust_1" })
                                                 .to_return(status: 200, body: { data: [] }.to_json)

      expect(cards.remove("card_ref_1")).to be(true)
      expect { cards.retrieve("card_ref_1") }.to raise_error(BmlTokenization::NotFoundError)
      expect(cards.list(customer_id: "cust_1")).to be_empty
    end

    it "raises a not-found error for an unknown/already-removed reference (US4-2)" do
      stub_request(:delete, "#{base}/cards-on-file/gone").to_return(status: 404, body: "{}")

      expect { cards.remove("gone") }.to raise_error(BmlTokenization::NotFoundError)
    end

    it "emits a remove audit record with no card data beyond the safe reference (FR-006a)" do
      stub_request(:delete, "#{base}/cards-on-file/card_ref_1").to_return(status: 200, body: "{}")

      cards.remove("card_ref_1", actor: "admin-3")

      expect(audit_sink.size).to eq(1)
      record = audit_sink.first
      expect(record.action).to eq("remove")
      expect(record.card_reference).to eq("card_ref_1")
      expect(record.actor).to include("admin-3")
    end

    it "raises a validation error naming a blank reference with no network call" do
      expect { cards.remove("") }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:reference) }
      expect(a_request(:any, /cards-on-file/)).not_to have_been_made
    end
  end
end
