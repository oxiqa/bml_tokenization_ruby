# bml_tokenization

A thin, contract-driven Ruby client for the Bank of Maldives tokenization / Connect
platform. A configured client object exposes per-resource classes; this release ships
the **Customers** resource (create, retrieve, list, update).

> **Security:** this library manages customer contact records only. It never accepts,
> stores, or logs a full card number (PAN), CVV/CVV2, PIN, track data, or any Sensitive
> Authentication Data (SAD).

## Installation

Add to your `Gemfile`:

```ruby
gem "bml_tokenization"
```

Then:

```bash
bundle install
```

## Configuring the client

The client selects an environment (`:sandbox` or `:production`) and injects credentials
on every request. The base URL is derived from the environment, so a sandbox client can
never route to production or vice versa.

```ruby
client = BmlTokenization::Client.new(
  api_key:     ENV["BML_API_KEY"],
  app_id:      ENV["BML_APP_ID"],
  environment: :sandbox            # or :production
  # logger:    Logger.new($stdout) # optional; log lines are masked + PII-minimized
)
```

## Customers resource

Reach the resource through `client.customers`.

### Create

Required: `first_name`, `last_name`, `email` (validated locally before any network call).
`phone` and `reference` are optional. Returns a `BmlTokenization::Customer` with the
platform-assigned `id`.

```ruby
customer = client.customers.create(
  first_name: "Aisha",
  last_name:  "Ali",
  email:      "aisha@example.mv",
  phone:      "+9607777777",   # optional
  reference:  "acct-42"        # optional
)

customer.id          # => "cust_..."
customer.first_name  # => "Aisha"
```

A missing or blank required field raises `BmlTokenization::ValidationError` (with
`#field` naming the offender) and makes **no** network call.

### Retrieve

```ruby
customer = client.customers.retrieve("cust_123")
```

An unknown identifier raises `BmlTokenization::NotFoundError`.

### List (pagination)

Page-number pagination. `page` defaults to 1; `page_size` defaults to 20 and must not
exceed 100 (an over-cap `page_size` is rejected locally, before any network call).
Returns a `BmlTokenization::CustomerListPage`.

```ruby
page = client.customers.list(page: 1, page_size: 20)

page.records    # => [BmlTokenization::Customer, ...]
page.page       # => 1
page.page_size  # => 20
page.has_next?  # => true / false
page.next_page  # => next page number, or nil on the final page
page.empty?     # => true when there are no results

page.each { |customer| puts customer.email }  # CustomerListPage is Enumerable
```

Listing when no customers exist, or requesting a page beyond the available results,
returns an **empty page** — not an error.

### Update (full replace)

`update` uses **full-replace** semantics: supply the complete record. Any mutable field
omitted from the record is **cleared** on the platform, not left unchanged. The same
required-field validation as `create` applies; the platform-assigned `id` is immutable.

```ruby
updated = client.customers.update("cust_123",
  first_name: "Aisha",
  last_name:  "Ali",
  email:      "aisha.new@example.mv"
  # phone/reference omitted here are CLEARED on the platform
)
```

## Errors

Every failure maps to a distinguishable subclass of `BmlTokenization::Error`:

| Class | Condition |
|-------|-----------|
| `ValidationError` | Missing/invalid field (local pre-remote or platform-reported). `#field` names the offender. |
| `NotFoundError` | Unknown customer identifier. |
| `ConflictError` | Duplicate per platform uniqueness rules. |
| `AuthenticationError` | Missing/invalid credentials or client configuration. |
| `ConfigurationError` | Setup problem detected before the request (e.g. non-TLS base URL). Subclass of `AuthenticationError`. |
| `AvailabilityError` | Remote outage or timeout. No partial record is returned. |

## Testing

Deterministic suite (no credentials — HTTP is stubbed with WebMock):

```bash
bundle exec rspec spec/contract spec/unit
```

Opt-in sandbox integration suite (skips cleanly when credentials are absent):

```bash
BML_ENV=sandbox BML_API_KEY=... BML_APP_ID=... \
  bundle exec rspec spec/integration/customers_sandbox_spec.rb
```
