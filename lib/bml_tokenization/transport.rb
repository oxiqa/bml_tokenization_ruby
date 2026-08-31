# frozen_string_literal: true

module BmlTokenization
  # Shared transport concern: a configurable per-request timeout plus a bounded
  # automatic retry on transient failures (FR-014, research R6/R7).
  #
  # Mixed into {Resource} so every resource behaves identically. A single
  # attempt is yielded to {#with_retries}; transient failures surfaced as an
  # {AvailabilityError} (connection error, timeout, 5xx) or a {RateLimitError}
  # (429) are retried up to +max_retries+ (default 2) with backoff — a 429
  # honouring any +Retry-After+ hint. Non-transient errors (validation,
  # not-found, auth, conflict) are never retried; they propagate on the first
  # attempt. When the budget is exhausted the last transient error is raised so
  # the caller receives a distinguishable availability/rate-limit error and no
  # partial record.
  module Transport
    # Wrap a single-attempt block with bounded retry on transient failures.
    #
    # max_retries:: maximum retries after the first attempt (default from client)
    # backoff::     base backoff seconds; exponential per retry (default from client)
    def with_retries(max_retries: default_max_retries, backoff: default_retry_backoff)
      attempt = 0
      begin
        yield
      rescue RateLimitError => e
        attempt += 1
        raise if attempt > max_retries

        pause(retry_after_seconds(e, attempt, backoff))
        retry
      rescue AvailabilityError
        attempt += 1
        raise if attempt > max_retries

        pause(backoff_seconds(attempt, backoff))
        retry
      end
    end

    # Apply the client's configurable per-request timeout to both the connect
    # and read phases (FR-014). No-op when the client exposes no timeout.
    def apply_timeouts(http)
      timeout = client.respond_to?(:timeout) ? client.timeout : nil
      return unless timeout

      http.open_timeout = timeout
      http.read_timeout = timeout
    end

    # Parse the server's Retry-After hint (seconds) from a 429 response, when
    # present, so a rate-limit retry can honour it (FR-014, R7).
    def retry_after_from(response)
      value = response["Retry-After"] || response["retry-after"]
      return nil if value.nil? || value.to_s.strip.empty?

      value.to_i
    end

    private

    def default_max_retries
      client.respond_to?(:max_retries) && client.max_retries ? client.max_retries : 2
    end

    def default_retry_backoff
      client.respond_to?(:retry_backoff) && client.retry_backoff ? client.retry_backoff : 0.5
    end

    # Sleep between attempts; skipped entirely when the computed wait is zero so
    # the deterministic test suite stays fast (configure backoff: 0).
    def pause(seconds)
      sleep(seconds) if seconds&.positive?
    end

    # Exponential backoff: backoff, 2*backoff, 4*backoff, ...
    def backoff_seconds(attempt, backoff)
      return 0 unless backoff&.positive?

      backoff * (2**(attempt - 1))
    end

    # Honour the server's Retry-After hint for a rate-limit retry when present,
    # otherwise fall back to exponential backoff.
    def retry_after_seconds(error, attempt, backoff)
      hint = error.retry_after
      return hint if hint && hint >= 0

      backoff_seconds(attempt, backoff)
    end
  end
end
