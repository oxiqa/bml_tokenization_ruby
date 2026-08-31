# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "bml_tokenization"
  spec.version       = "0.1.0"
  spec.authors       = ["Bank of Maldives Integration"]
  spec.summary       = "Ruby client library for the Bank of Maldives tokenization / Connect platform."
  spec.description   = "A thin, contract-driven Ruby client for BML platform resources " \
                       "(customers, cards-on-file, transactions, tokenization). Handles no " \
                       "card data or Sensitive Authentication Data."
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.7"

  spec.files = Dir.glob("lib/**/*.rb") + %w[LICENSE]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rspec", "~> 3.10"
  spec.add_development_dependency "rubocop", "~> 1.20"
  spec.add_development_dependency "webmock", "~> 3.14"
end
