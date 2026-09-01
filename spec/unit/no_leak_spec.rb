# frozen_string_literal: true

# Cross-cutting leakage sweep (FR-003, FR-012, FR-013, SC-002): across all three
# operations, assert NO full PAN/CVV/card-handle appears in any return value,
# inspect/to_s, structured log, or audit record — even when the platform leaks
# card data back on a response.
RSpec.describe "Tokenization no-leak sweep" do
  let(:base) { BmlTokenization::Client::BASE_URLS[:sandbox] }
  let(:audit_sink) { [] }
  let(:logged) { [] }
  let(:logger) do
    instance_double("Logger").tap { |l| allow(l).to receive(:info) { |entry| logged << entry } }
  end
  let(:client) do
    BmlTokenization::Client.new(
      api_key: "key", app_id: "app", environment: :sandbox,
      retry_backoff: 0, audit_sink: audit_sink, logger: logger
    )
  end
  let(:tokens) { client.tokenization }

  # A response the platform should never send, but which the library must defend
  # against: full PAN, CVV, and the single-use handle echoed back.
  let(:leaky) do
    { token_reference: "tok_ref_1", scheme: "visa", last4: "4242", expiry_month: 12,
      expiry_year: 2028, status: "active",
      card_number: "4111111111111111", cvv: "123", card_handle: "handle_secret" }
  end

  def full_dump(return_value)
    [
      return_value.to_h.to_s, return_value.inspect, return_value.to_s,
      audit_sink.map { |r| r.to_h.to_s }.join, logged.map(&:to_s).join
    ].join
  end

  def assert_no_sensitive(dump)
    expect(dump).not_to include("4111111111111111")
    expect(dump).not_to include("handle_secret")
    expect(dump).not_to match(/\bcvv\b.*123/)
    expect(dump).not_to match(/\b(?:\d[ -]?){12,19}\b/)
  end

  it "leaks nothing sensitive on tokenize" do
    stub_request(:post, "#{base}/tokens").to_return(status: 201, body: leaky.to_json)

    token = tokens.tokenize("handle_secret", actor: "user-1")

    assert_no_sensitive(full_dump(token))
    expect(token.reference).to eq("tok_ref_1") # the safe reference still flows through
  end

  it "leaks nothing sensitive on retrieve" do
    stub_request(:get, "#{base}/tokens/tok_ref_1").to_return(status: 200, body: leaky.to_json)

    token = tokens.retrieve("tok_ref_1")

    assert_no_sensitive(full_dump(token))
  end

  it "leaks nothing sensitive on revoke" do
    stub_request(:post, "#{base}/tokens/tok_ref_1/revoke")
      .to_return(status: 200, body: leaky.merge(status: "revoked").to_json)

    token = tokens.revoke("tok_ref_1")

    assert_no_sensitive(full_dump(token))
  end
end
