# frozen_string_literal: true

# Foundational unit spec for the shared Masking concern as it applies to
# tokenization (FR-003, FR-013, R7). Asserts that a PAN, CVV, and single-use
# card handle are scrubbed from any structured value before it can reach a log
# line, and that a PAN-shaped run inside a free-form string is redacted.
RSpec.describe BmlTokenization::Masking do
  describe ".scrub" do
    it "filters sensitive keys (pan, cvv, card_handle, token, handle) regardless of the emitting resource" do
      scrubbed = described_class.scrub(
        pan: "4111111111111111", cvv: "123", card_handle: "handle_x",
        token: "raw", handle: "h", operation: "tokenize", token_reference: "tok_1"
      )

      expect(scrubbed[:pan]).to eq("[FILTERED]")
      expect(scrubbed[:cvv]).to eq("[FILTERED]")
      expect(scrubbed[:card_handle]).to eq("[FILTERED]")
      expect(scrubbed[:handle]).to eq("[FILTERED]")
      # a safe token reference and the operation are preserved for correlation
      expect(scrubbed[:operation]).to eq("tokenize")
      expect(scrubbed[:token_reference]).to eq("tok_1")
    end

    it "redacts a PAN-shaped run embedded in a free-form string" do
      scrubbed = described_class.scrub(note: "captured 4111 1111 1111 1111 at pos")

      expect(scrubbed[:note]).not_to match(/\b(?:\d[ -]?){12,19}\b/)
      expect(scrubbed[:note]).to include("[REDACTED]")
    end

    it "recurses into nested hashes and arrays" do
      scrubbed = described_class.scrub(events: [{ pan: "4111111111111111", ref: "tok_1" }])

      expect(scrubbed[:events].first[:pan]).to eq("[FILTERED]")
      expect(scrubbed[:events].first[:ref]).to eq("tok_1")
    end
  end
end
