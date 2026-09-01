# frozen_string_literal: true

# Token-strength inspection (FR-006, SC-007). The library neither generates nor
# shortens the token — the platform issues the opaque reference and owns its
# non-sequentiality (recorded in research.md R4). What the library CAN and MUST
# guarantee is that it derives nothing about the reference from the card: over a
# sample of issued/stubbed tokens, the reference shares no derivable substring
# with the PAN fragment (last4), and the library never reconstructs a PAN from it.
RSpec.describe "Token reference strength" do
  let(:base) { BmlTokenization::Client::BASE_URLS[:sandbox] }
  let(:client) { BmlTokenization::Client.new(api_key: "key", app_id: "app", environment: :sandbox, retry_backoff: 0) }
  let(:tokens) { client.tokenization }

  # A representative sample of platform-issued tokens (opaque references).
  let(:sample) do
    [
      { token_reference: "tok_9f3a8c21", last4: "4242" },
      { token_reference: "tok_b7e10d55", last4: "1881" },
      { token_reference: "tok_02c4aa9e", last4: "0004" }
    ]
  end

  it "yields references that embed no derivable substring of the card's last4" do
    sample.each do |row|
      stub_request(:post, "#{base}/tokens")
        .to_return(status: 201, body: row.merge(scheme: "visa", status: "active").to_json)

      token = tokens.tokenize("handle_#{row[:last4]}")

      expect(token.reference).not_to include(row[:last4])
      # and the reference is not simply the last4 with a fixed prefix/suffix
      expect(token.reference.gsub(/\D/, "")).not_to include(row[:last4])
    end
  end

  it "provides no way to reconstruct a PAN from the reference (non-reversible, FR-006)" do
    stub_request(:post, "#{base}/tokens")
      .to_return(status: 201, body: sample.first.merge(scheme: "visa", status: "active").to_json)

    token = tokens.tokenize("handle_x")

    expect(token).not_to respond_to(:card_number)
    expect(token.to_h.to_s).not_to match(/\b(?:\d[ -]?){12,19}\b/)
  end
end
