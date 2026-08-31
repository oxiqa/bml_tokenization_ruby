# frozen_string_literal: true

RSpec.describe BmlTokenization::Customer do
  let(:attributes) do
    {
      "id" => "cust_123",
      "first_name" => "Aisha",
      "last_name" => "Ali",
      "email" => "aisha@example.mv",
      "phone" => "+9607777777",
      "reference" => "acct-42",
      "created_at" => "2026-08-18T00:00:00Z",
      "updated_at" => "2026-08-19T00:00:00Z"
    }
  end

  it "exposes exactly the customer contact fields" do
    expect(described_class::ATTRIBUTES).to contain_exactly(
      :id, :first_name, :last_name, :email, :phone, :reference, :created_at, :updated_at
    )
  end

  it "reads every attribute from a response hash (string keys)" do
    customer = described_class.from_response(attributes)

    expect(customer.id).to eq("cust_123")
    expect(customer.first_name).to eq("Aisha")
    expect(customer.last_name).to eq("Ali")
    expect(customer.email).to eq("aisha@example.mv")
    expect(customer.phone).to eq("+9607777777")
    expect(customer.reference).to eq("acct-42")
    expect(customer.created_at).to eq("2026-08-18T00:00:00Z")
    expect(customer.updated_at).to eq("2026-08-19T00:00:00Z")
  end

  it "accepts symbol keys as well" do
    customer = described_class.new(id: "cust_9", first_name: "Sara")
    expect(customer.id).to eq("cust_9")
    expect(customer.first_name).to eq("Sara")
  end

  describe "no SAD/PAN exposure" do
    let(:with_card_data) do
      attributes.merge(
        "card_number" => "4111111111111111",
        "pan" => "4111111111111111",
        "cvv" => "123",
        "pin" => "0000",
        "track2" => "4111111111111111=25121011000012300000"
      )
    end

    it "does not define any SAD/PAN attribute reader" do
      %i[card_number pan cvv cvv2 pin track track1 track2].each do |forbidden|
        expect(described_class.instance_methods).not_to include(forbidden)
        expect(described_class::ATTRIBUTES).not_to include(forbidden)
      end
    end

    it "silently discards card data present in a response" do
      customer = described_class.from_response(with_card_data)

      expect(customer).not_to respond_to(:card_number)
      expect(customer).not_to respond_to(:pan)
      expect(customer).not_to respond_to(:cvv)
    end

    it "never serializes card data" do
      customer = described_class.from_response(with_card_data)

      serialized = customer.to_h.to_s + customer.inspect
      expect(serialized).not_to include("4111111111111111")
      expect(serialized).not_to include("track2")
      expect(customer.to_h.keys).to match_array(described_class::ATTRIBUTES)
    end
  end

  it "compares by value" do
    expect(described_class.new(attributes)).to eq(described_class.new(attributes))
    expect(described_class.new(attributes)).not_to eq(described_class.new(id: "other"))
  end
end
