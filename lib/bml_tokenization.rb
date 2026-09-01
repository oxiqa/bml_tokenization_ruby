# frozen_string_literal: true

require "bml_tokenization/version"
require "bml_tokenization/errors"
require "bml_tokenization/masking"
require "bml_tokenization/transport"
require "bml_tokenization/resource"
require "bml_tokenization/audit"
require "bml_tokenization/customer"
require "bml_tokenization/customer_list_page"
require "bml_tokenization/customers"
require "bml_tokenization/card_on_file"
require "bml_tokenization/card_on_file_list"
require "bml_tokenization/cards_on_file"
require "bml_tokenization/transaction"
require "bml_tokenization/transaction_list"
require "bml_tokenization/transactions"
require "bml_tokenization/token"
require "bml_tokenization/tokenization"
require "bml_tokenization/client"

# Ruby client library for the Bank of Maldives tokenization / Connect platform.
#
# This library manages customer contact records only; it never accepts, stores,
# or logs full card numbers (PAN) or Sensitive Authentication Data (SAD).
module BmlTokenization
end
