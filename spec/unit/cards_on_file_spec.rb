# frozen_string_literal: true

# Unit spec for the CardsOnFile resource: local validation before any remote
# call, idempotency normalization, audit emission on state changes (not reads),
# and no SAD/PAN/handle leakage across any output or log (FR-003, FR-007,
# FR-013, FR-015, SC-002).
RSpec.describe BmlTokenization::CardsOnFile do
  let(:base) { BmlTokenization::Client::BASE_URLS[:sandbox] }
  let(:audit_sink) { [] }
  let(:logger) { instance_double("Logger", info: nil) }
  let(:client) do
    BmlTokenization::Client.new(
      api_key: "key", app_id: "app", environment: :sandbox,
      retry_backoff: 0, audit_sink: audit_sink, logger: logger
    )
  end
  let(:cards) { client.cards_on_file }
  let(:card_json) do
    { reference: "card_ref_1", customer_id: "cust_1", scheme: "visa", last_four: "4242",
      expiry_month: 12, expiry_year: 2030, status: "active" }
  end

  describe "local validation runs before any remote call (FR-007)" do
    it "rejects a missing customer_id / card_handle on store, naming the field" do
      expect { cards.store(customer_id: nil, card_handle: "tok") }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:customer_id) }
      expect { cards.store(customer_id: "c", card_handle: " ") }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:card_handle) }
      expect(a_request(:any, /cards-on-file/)).not_to have_been_made
    end

    it "rejects a blank customer_id on list and a blank reference on retrieve/remove" do
      expect { cards.list(customer_id: "") }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:customer_id) }
      expect { cards.retrieve(nil) }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:reference) }
      expect { cards.remove("   ") }
        .to raise_error(BmlTokenization::ValidationError) { |e| expect(e.field).to eq(:reference) }
      expect(a_request(:any, /cards-on-file/)).not_to have_been_made
    end
  end

  describe "idempotent re-store normalization (FR-013)" do
    it "returns the existing record when the platform reports a 409 with the reference (no duplicate)" do
      stub_request(:post, "#{base}/cards-on-file").to_return(status: 409, body: card_json.to_json)

      card = cards.store(customer_id: "cust_1", card_handle: "tok")

      expect(card.reference).to eq("card_ref_1")
      # exactly one POST — the library did not attempt a second create
      expect(a_request(:post, "#{base}/cards-on-file")).to have_been_made.times(1)
    end
  end

  describe "audit emission — state changes only (FR-015, FR-006a)" do
    it "emits a store audit record and a remove audit record" do
      stub_request(:post, "#{base}/cards-on-file").to_return(status: 201, body: card_json.to_json)
      stub_request(:delete, "#{base}/cards-on-file/card_ref_1").to_return(status: 200, body: "{}")

      cards.store(customer_id: "cust_1", card_handle: "tok")
      cards.remove("card_ref_1")

      expect(audit_sink.map(&:action)).to eq(%w[store remove])
      expect(audit_sink.map(&:card_reference)).to eq(%w[card_ref_1 card_ref_1])
    end

    it "emits NO audit record for list or retrieve (reads)" do
      stub_request(:get, "#{base}/cards-on-file").with(query: { customer_id: "cust_1" })
                                                 .to_return(status: 200, body: { data: [card_json] }.to_json)
      stub_request(:get, "#{base}/cards-on-file/card_ref_1").to_return(status: 200, body: card_json.to_json)

      cards.list(customer_id: "cust_1")
      cards.retrieve("card_ref_1")

      expect(audit_sink).to be_empty
    end
  end

  # T034 — no SAD/PAN/handle leakage across all four operations (FR-003, SC-002)
  describe "no SAD/PAN/handle leakage across operations (FR-003, SC-002)" do
    it "never logs the single-use handle, PAN, or CVV on store" do
      stub_request(:post, "#{base}/cards-on-file").to_return(status: 201, body: card_json.to_json)

      logged = []
      allow(logger).to receive(:info) { |entry| logged << entry }

      cards.store(customer_id: "cust_1", card_handle: "tok_secret_handle", actor: "user-1")

      dump = logged.map(&:to_s).join
      expect(dump).not_to include("tok_secret_handle")
      expect(dump).to include("card_ref_1") # safe reference is logged
    end

    it "never exposes card data the platform leaks back on any read/return" do
      leaky = card_json.merge(card_number: "4111111111111111", cvv: "123", card_handle: "tok_x")
      stub_request(:get, "#{base}/cards-on-file/card_ref_1").to_return(status: 200, body: leaky.to_json)

      card = cards.retrieve("card_ref_1")

      serialized = card.to_h.to_s + card.inspect
      expect(serialized).not_to include("4111111111111111")
      expect(serialized).not_to include("tok_x")
      expect(card).not_to respond_to(:card_number)
    end

    it "does not include card data beyond the safe reference in an audit record" do
      stub_request(:post, "#{base}/cards-on-file").to_return(status: 201, body: card_json.to_json)

      cards.store(customer_id: "cust_1", card_handle: "tok_secret_handle")

      dump = audit_sink.first.to_h.to_s
      expect(dump).not_to include("tok_secret_handle")
      expect(dump).not_to include("4242") # not even the masked last_four
      expect(dump).to include("card_ref_1")
    end
  end
end
