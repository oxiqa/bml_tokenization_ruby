# frozen_string_literal: true

# Unit spec for the TransactionList page (data-model.md, FR-004, R7): records +
# page/page_size/total_count metadata; default page size 20; an empty page is a
# valid result, not an error.
RSpec.describe BmlTokenization::TransactionList do
  def txn(id)
    BmlTokenization::Transaction.new(id: id)
  end

  it "echoes page and page_size back to the caller" do
    page = described_class.new(records: [], page: 2, page_size: 50)

    expect(page.page).to eq(2)
    expect(page.page_size).to eq(50)
  end

  it "builds Transaction records from a response and exposes total_count" do
    page = described_class.from_response(
      { "records" => [{ "id" => "txn_1", "status" => "pending" }, { "id" => "txn_2", "status" => "succeeded" }],
        "page" => 1, "page_size" => 20, "total_count" => 2 },
      page: 1, page_size: 20
    )

    expect(page.records).to all(be_a(BmlTokenization::Transaction))
    expect(page.records.map(&:id)).to eq(%w[txn_1 txn_2])
    expect(page.total_count).to eq(2)
    expect(page.size).to eq(2)
  end

  it "accepts either a data or records array from the platform" do
    page = described_class.from_response({ "data" => [{ "id" => "txn_9" }] }, page: 1, page_size: 20)

    expect(page.records.map(&:id)).to eq(%w[txn_9])
  end

  describe "empty pages are never an error (US3-5, FR-004)" do
    it "is empty when there are no records at all" do
      page = described_class.new(records: [], page: 1, page_size: 20)

      expect(page).to be_empty
      expect(page.records).to eq([])
    end

    it "is empty when a page beyond the results is requested" do
      page = described_class.from_response({ "records" => [], "page" => 99 }, page: 99, page_size: 20)

      expect(page).to be_empty
    end
  end

  it "is enumerable over its records" do
    page = described_class.new(records: [txn("a"), txn("b")], page: 1, page_size: 20)

    expect(page).to be_a(Enumerable)
    expect(page.map(&:id)).to eq(%w[a b])
  end
end
