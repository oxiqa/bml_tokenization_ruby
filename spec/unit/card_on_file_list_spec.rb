# frozen_string_literal: true

# Unit spec for the CardOnFileList value object (data-model.md, R11): holds a
# customer_id and records (each a CardOnFile); an empty set is valid (not an
# error); no pagination fields are required.
RSpec.describe BmlTokenization::CardOnFileList do
  it "wraps a customer's cards, each a CardOnFile with a safe reference + masked summary" do
    response = {
      "customer_id" => "cust_1",
      "data" => [
        { "reference" => "r1", "customer_id" => "cust_1", "scheme" => "visa", "last_four" => "4242" },
        { "reference" => "r2", "customer_id" => "cust_1", "scheme" => "mastercard", "last_four" => "1111" }
      ]
    }

    list = described_class.from_response(response, customer_id: "cust_1")

    expect(list.customer_id).to eq("cust_1")
    expect(list.records).to all(be_a(BmlTokenization::CardOnFile))
    expect(list.size).to eq(2)
    expect(list.map(&:reference)).to eq(%w[r1 r2])
  end

  it "treats an empty data array as a valid empty list, not an error" do
    list = described_class.from_response({ "data" => [] }, customer_id: "cust_1")

    expect(list).to be_empty
    expect(list.size).to eq(0)
    expect(list.customer_id).to eq("cust_1")
  end

  it "treats a missing data key as an empty list" do
    list = described_class.from_response({}, customer_id: "cust_1")

    expect(list).to be_empty
  end

  it "is enumerable and requires no pagination fields" do
    list = described_class.from_response(
      { "data" => [{ "reference" => "r1" }] }, customer_id: "cust_1"
    )

    expect(list).to be_a(Enumerable)
    expect(list.first).to be_a(BmlTokenization::CardOnFile)
    expect(list).not_to respond_to(:page)
    expect(list).not_to respond_to(:next_page)
  end
end
