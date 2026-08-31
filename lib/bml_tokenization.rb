# frozen_string_literal: true

require "bml_tokenization/version"
require "bml_tokenization/errors"
require "bml_tokenization/masking"
require "bml_tokenization/resource"
require "bml_tokenization/customer"
require "bml_tokenization/customer_list_page"
require "bml_tokenization/customers"
require "bml_tokenization/client"

# Ruby client library for the Bank of Maldives tokenization / Connect platform.
#
# This library manages customer contact records only; it never accepts, stores,
# or logs full card numbers (PAN) or Sensitive Authentication Data (SAD).
module BmlTokenization
end
