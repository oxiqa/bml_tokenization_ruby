# frozen_string_literal: true

RSpec.describe BmlTokenization::CustomerListPage do
  def customer(id)
    BmlTokenization::Customer.new(id: id)
  end

  it "echoes page and page_size back to the caller" do
    page = described_class.new(records: [], page: 3, page_size: 25)

    expect(page.page).to eq(3)
    expect(page.page_size).to eq(25)
  end

  describe "empty pages (never an error)" do
    it "is empty when there are no records at all" do
      page = described_class.new(records: [], page: 1, page_size: 20)

      expect(page).to be_empty
      expect(page.records).to eq([])
    end

    it "is empty when a page beyond the results is requested" do
      page = described_class.from_response({ "data" => [], "page" => 99, "has_next" => false },
                                           page: 99, page_size: 20)

      expect(page).to be_empty
      expect(page.records).to eq([])
    end
  end

  describe "next-page derivation" do
    it "reports a further page and next_page number on a non-final page" do
      page = described_class.new(records: [customer("a")], page: 1, page_size: 20, has_next: true)

      expect(page.has_next?).to be(true)
      expect(page.next_page).to eq(2)
    end

    it "honors an explicit next_page when provided" do
      page = described_class.new(records: [customer("a")], page: 1, page_size: 20,
                                 has_next: true, next_page: 7)

      expect(page.next_page).to eq(7)
    end

    it "has no next page on the final page" do
      page = described_class.new(records: [customer("a")], page: 2, page_size: 20, has_next: false)

      expect(page.has_next?).to be(false)
      expect(page.next_page).to be_nil
    end
  end

  it "builds records from a response data array" do
    page = described_class.from_response(
      { "data" => [{ "id" => "c1" }, { "id" => "c2" }], "page" => 1, "page_size" => 20, "has_next" => true },
      page: 1, page_size: 20
    )

    expect(page.records.map(&:id)).to eq(%w[c1 c2])
    expect(page.records).to all(be_a(BmlTokenization::Customer))
    expect(page.size).to eq(2)
  end

  it "is enumerable over its records" do
    page = described_class.new(records: [customer("a"), customer("b")], page: 1, page_size: 20)
    expect(page.map(&:id)).to eq(%w[a b])
  end
end
