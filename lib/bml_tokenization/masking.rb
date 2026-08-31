# frozen_string_literal: true

module BmlTokenization
  # Shared masking + structured-logging concern.
  #
  # Although the customer resource carries no card data or Sensitive
  # Authentication Data (SAD), this concern guards every log line against
  # accidental leakage of a PAN/CVV/PIN-like value and minimizes customer PII
  # (FR-010, Constitution IV). It is defensive-by-default: any key that looks
  # sensitive is filtered, and any string that looks like a card number is
  # redacted, regardless of the resource emitting it.
  module Masking
    module_function

    # Keys whose values must never be logged verbatim.
    SENSITIVE_KEYS = %w[
      pan card_number cardnumber number cvv cvv2 cvc cvn pin
      track track1 track2 track_data password secret token
      api_key apikey app_id authorization auth
    ].freeze

    # Customer PII keys that are minimized (partially masked) rather than
    # dropped entirely, so a log line can still correlate a record.
    PII_KEYS = %w[email phone first_name last_name].freeze

    # A 12–19 digit run that looks like a PAN, allowing space/dash separators.
    PAN_PATTERN = /\b(?:\d[ -]?){12,19}\b/.freeze

    # Recursively scrub a value for safe logging.
    def scrub(value)
      case value
      when Hash
        scrub_hash(value)
      when Array
        value.map { |element| scrub(element) }
      when String
        mask_pan(value)
      else
        value
      end
    end

    def scrub_hash(hash)
      hash.each_with_object({}) do |(key, val), acc|
        name = key.to_s.downcase
        acc[key] =
          if sensitive_key?(name)
            "[FILTERED]"
          elsif pii_key?(name) && val.is_a?(String)
            minimize_pii(val)
          else
            scrub(val)
          end
      end
    end

    def sensitive_key?(name)
      SENSITIVE_KEYS.include?(name)
    end

    def pii_key?(name)
      PII_KEYS.include?(name)
    end

    # Redact anything PAN-shaped inside a free-form string.
    def mask_pan(string)
      string.gsub(PAN_PATTERN) do |match|
        digits = match.gsub(/[ -]/, "")
        digits.length.between?(12, 19) ? "[REDACTED]" : match
      end
    end

    # Reduce PII to a minimal, non-reversible hint for correlation only.
    def minimize_pii(string)
      return string if string.empty?

      visible = string[0]
      "#{visible}#{'*' * [string.length - 1, 1].max}"
    end
  end
end
