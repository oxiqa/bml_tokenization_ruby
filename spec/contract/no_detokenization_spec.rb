# frozen_string_literal: true

# Guards against a detokenize/reveal-PAN regression (FR-006a, Clarification Q1):
# the public API MUST expose no method that returns or reconstructs a full card
# number, on either the resource or the Token it yields.
RSpec.describe "Tokenization has no detokenization surface" do
  let(:client) { BmlTokenization::Client.new(api_key: "key", app_id: "app", environment: :sandbox) }
  let(:tokens) { client.tokenization }

  # Any method name that would imply revealing/reconstructing card data.
  let(:forbidden_methods) do
    %i[
      detokenize decrypt reveal reveal_pan unmask pan card_number full_number
      card_pan raw_pan cvv security_code
    ]
  end

  it "exposes no reveal-PAN method on the Tokenization resource" do
    forbidden_methods.each do |name|
      expect(tokens).not_to respond_to(name), "Tokenization must not expose ##{name}"
    end
    expect(tokens.public_methods(false).sort).to eq(%i[retrieve revoke tokenize])
  end

  it "exposes no reveal-PAN method on the Token value object" do
    token = BmlTokenization::Token.from_response(
      "token_reference" => "tok_1", "scheme" => "visa", "last4" => "4242", "status" => "active"
    )

    forbidden_methods.each do |name|
      expect(token).not_to respond_to(name), "Token must not expose ##{name}"
    end
  end
end
