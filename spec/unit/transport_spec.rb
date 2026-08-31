# frozen_string_literal: true

# Unit spec for the shared transport concern (FR-014, research R6/R7): a
# configurable timeout, bounded retry (<=2) with backoff on transient failures,
# no retry of non-transient errors, 429 retried honouring Retry-After then a
# distinguishable rate-limit error, and retry-exhausted -> availability error.
RSpec.describe BmlTokenization::Transport do
  # Minimal harness mixing in the concern with a stubbed client config.
  let(:harness_class) do
    Class.new do
      include BmlTokenization::Transport

      attr_reader :client

      def initialize(client)
        @client = client
      end

      def run(&block)
        with_retries(&block)
      end
    end
  end

  let(:client) do
    instance_double(BmlTokenization::Client, max_retries: 2, retry_backoff: 0)
  end
  let(:harness) { harness_class.new(client) }

  it "does not retry on success and returns the block value" do
    calls = 0
    result = harness.run do
      calls += 1
      :ok
    end

    expect(result).to eq(:ok)
    expect(calls).to eq(1)
  end

  it "retries a transient availability failure up to 2 times, then succeeds" do
    calls = 0
    result = harness.run do
      calls += 1
      raise BmlTokenization::AvailabilityError, "boom" if calls < 3

      :recovered
    end

    expect(result).to eq(:recovered)
    expect(calls).to eq(3) # initial attempt + 2 retries
  end

  it "raises a distinguishable availability error once retries are exhausted (no partial result)" do
    calls = 0
    expect do
      harness.run do
        calls += 1
        raise BmlTokenization::AvailabilityError, "down"
      end
    end.to raise_error(BmlTokenization::AvailabilityError)

    expect(calls).to eq(3) # bounded: initial + 2 retries only
  end

  it "does not retry a non-transient error (validation propagates on first attempt)" do
    calls = 0
    expect do
      harness.run do
        calls += 1
        raise BmlTokenization::ValidationError.new("bad", field: :x)
      end
    end.to raise_error(BmlTokenization::ValidationError)

    expect(calls).to eq(1)
  end

  %i[NotFoundError AuthenticationError ConflictError].each do |name|
    it "does not retry a #{name}" do
      calls = 0
      klass = BmlTokenization.const_get(name)
      expect do
        harness.run do
          calls += 1
          raise klass
        end
      end.to raise_error(klass)
      expect(calls).to eq(1)
    end
  end

  it "retries a 429 rate-limit within the budget, honouring Retry-After, then succeeds" do
    calls = 0
    result = harness.run do
      calls += 1
      raise BmlTokenization::RateLimitError.new("slow down", retry_after: 0) if calls < 2

      :ok
    end

    expect(result).to eq(:ok)
    expect(calls).to eq(2)
  end

  it "honours the Retry-After hint over exponential backoff for a rate-limit retry" do
    error = BmlTokenization::RateLimitError.new("limited", retry_after: 7)

    expect(harness.send(:retry_after_seconds, error, 1, 0.5)).to eq(7)
  end

  it "raises a distinguishable rate-limit error when still limited after retries" do
    calls = 0
    expect do
      harness.run do
        calls += 1
        raise BmlTokenization::RateLimitError.new("limited", retry_after: 0)
      end
    end.to raise_error(BmlTokenization::RateLimitError)

    expect(calls).to eq(3) # bounded to initial + 2 retries
  end

  it "honours a configured max_retries of 0 (no retry)" do
    allow(client).to receive(:max_retries).and_return(0)
    calls = 0
    expect do
      harness.run do
        calls += 1
        raise BmlTokenization::AvailabilityError
      end
    end.to raise_error(BmlTokenization::AvailabilityError)

    expect(calls).to eq(1)
  end

  it "computes an exponential backoff (with backoff) between retries" do
    expect(harness.send(:backoff_seconds, 1, 0.5)).to eq(0.5)
    expect(harness.send(:backoff_seconds, 2, 0.5)).to eq(1.0)
    expect(harness.send(:backoff_seconds, 3, 0.5)).to eq(2.0)
    expect(harness.send(:backoff_seconds, 1, 0)).to eq(0) # no wait when backoff disabled
  end

  # The configurable per-request timeout is applied by Resource#apply_timeouts
  # from the client's #timeout; here we assert the concern reads the client
  # policy so the timeout/retry budget is configurable (FR-014).
  it "reads its retry budget from the client configuration" do
    expect(client).to receive(:max_retries).at_least(:once).and_return(2)
    harness.run { :ok }
  end
end
