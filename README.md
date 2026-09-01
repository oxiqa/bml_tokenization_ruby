# bml_tokenization

A thin, contract-driven Ruby client for the Bank of Maldives tokenization / Connect
platform. A configured client object exposes per-resource classes; this release ships
the **Customers** resource (create, retrieve, list, update), the **Cards-on-file**
resource (store, list, retrieve, remove), and the **Transactions** resource (create,
retrieve, list).

> **Security:** this library never accepts, stores, or logs a full card number (PAN),
> CVV/CVV2, PIN, track data, the single-use card handle, or any Sensitive Authentication
> Data (SAD). A stored card is exposed only as a safe reference plus a masked summary
> (scheme, last four, expiry). A payment's hosted redirect URL is treated as a completion
> secret and is never logged or placed in an audit record.

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
  api_key:       ENV["BML_API_KEY"],
  app_id:        ENV["BML_APP_ID"],
  environment:   :sandbox,           # or :production
  # logger:      Logger.new($stdout) # optional; log lines are masked + PII-minimized
  # timeout:       30,               # per-request timeout in seconds (default 30)
  # max_retries:   2,                # transient-failure retries after the first attempt
  # retry_backoff: 0.5,              # base backoff seconds between retries (exponential)
  # audit_sink:  ->(record) { ... }  # optional; receives an audit record on state changes
)
```

### Timeout, retry, and rate-limiting

Every request runs within `timeout` seconds and, on **transient** failures (connection
error, timeout, 5xx, or 429), is retried up to `max_retries` times with exponential
backoff. A `429` honours the server's `Retry-After` hint. **Non-transient** errors
(validation, not-found, auth, conflict) are never retried. When the budget is exhausted
the client raises a distinguishable `AvailabilityError` (outage/timeout) or
`RateLimitError` (still rate-limited) and returns **no partial record**.

### Audit records (state changes)

State-changing operations emit an audit record capturing **who** (the configured App ID
plus an optional integrator-supplied `actor:`), **what** (the operation and the affected
safe identifier), **when**, and the **outcome** — and never any card data beyond a safe
reference, nor a hosted payment URL. This covers card-on-file `store`/`remove` and, for
transactions, both `create` **and** `retrieve` (per FR-012). Card-on-file reads (`list`,
`retrieve`) and transaction `list` are not audited. Provide an `audit_sink` (any object
responding to `#call` or `#<<`) to receive each record.

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

## Cards-on-file resource

Reach the resource through `client.cards_on_file`. A card is stored from a pre-tokenized,
**single-use card handle** produced by a hosted capture step — the library never receives
a raw PAN or CVV. A stored card is represented only by a safe `reference` plus a masked
summary and is returned as a `BmlTokenization::CardOnFile`.

### Store

Required: `customer_id` and `card_handle` (validated locally before any network call).
Optional `actor:` is recorded in the audit record. Storing a card the customer already has
on file is **idempotent** — the existing record is returned and no duplicate is created.

```ruby
card = client.cards_on_file.store(
  customer_id: "cust_123",
  card_handle: "handle_from_hosted_capture",  # single-use
  actor:       "user-42"                       # optional, for the audit record
)

card.reference     # => "card_ref_..."  (safe reference; use for retrieve/remove)
card.scheme        # => "visa"
card.last_four     # => "4242"          (the only PAN fragment ever exposed)
card.expiry_month  # => 12
card.expiry_year   # => 2030
card.expired?      # => false           (derived convenience; makes no payment decision)
```

A missing/blank `customer_id` or `card_handle` raises `ValidationError` (with `#field`
naming the offender) and makes **no** network call.

### List

Returns a `BmlTokenization::CardOnFileList` of **all** of a customer's stored cards (no
pagination). A customer with no cards yields an **empty** list — not an error.

```ruby
list = client.cards_on_file.list(customer_id: "cust_123")

list.records  # => [BmlTokenization::CardOnFile, ...]
list.empty?   # => true when the customer has no stored cards
list.each { |card| puts card.reference }  # CardOnFileList is Enumerable
```

### Retrieve

```ruby
card = client.cards_on_file.retrieve("card_ref_123")
card.expired?  # expiry/validity is discoverable
```

An unknown reference raises `BmlTokenization::NotFoundError`.

### Remove (permanent)

Permanently deletes the stored card: afterward it is absent from the customer's list and
retrieval returns `NotFoundError`. It is not recoverable. Removing an unknown or
already-removed reference raises `NotFoundError` and affects no other card. Emits a
`remove` audit record.

```ruby
client.cards_on_file.remove("card_ref_123", actor: "user-42")  # => true
```

## Transactions resource

Reach the resource through `client.transactions`. A transaction is a payment for an
**existing customer**; the amount is a **positive integer in MVR minor units** (e.g.
`15000` = MVR 150.00) and the currency is **`"MVR"` only** — both validated locally
before any network call. A transaction is returned as a `BmlTokenization::Transaction`
whose `status` is one of four values: `pending`, `succeeded`, `failed`, `cancelled`.

### Create

`create` has two completion paths, selected by whether a stored-card safe reference is
supplied:

- **Redirect path** (no `card_reference`): a `return_url` is **required**. Returns a
  `pending` transaction carrying a hosted `payment_url` to send the customer's browser to.
- **Stored-card path** (`card_reference:` given): the payment is charged **server-side**
  with no redirect; the returned `status` (`succeeded`/`failed`) reflects the outcome and
  there is **no** `payment_url`.

Required: `customer_id`, `amount`, `currency` (`"MVR"`), `reference`. Optional `actor:` is
recorded in the audit record.

```ruby
# Redirect path
txn = client.transactions.create(
  customer_id: "cust_123",
  amount:      15_000,                          # positive integer, MVR minor units
  currency:    "MVR",
  reference:   "order-8842",                    # your idempotency key (globally unique)
  return_url:  "https://merchant.example/return",
  actor:       "user-42"                        # optional, for the audit record
)

txn.id           # => "txn_..."
txn.status       # => "pending"
txn.payment_url  # => "https://connect.bml.example/pay/txn_..."  (send the customer here)

# Stored-card path (charged server-side, no redirect)
charged = client.transactions.create(
  customer_id:    "cust_123",
  amount:         15_000,
  currency:       "MVR",
  reference:      "order-8843",
  card_reference: "card_ref_123"                # a card-on-file safe reference
)
charged.status       # => "succeeded" / "failed"
charged.payment_url  # => nil
```

Local validation (no network call on failure) raises `ValidationError` with `#field`
naming the offender: a missing required field, a non-integer/zero/negative `amount`, a
non-`"MVR"` `currency`, or a missing `return_url` on the redirect path.

**Idempotency & conflict (on the global `reference`):** repeating a `create` with the
**same** `reference` **and identical** material parameters returns the **existing**
transaction — no second charge. Reusing a `reference` with a **differing** material
parameter (amount, currency, customer, or card) raises `ConflictError` naming the
mismatch. The `reference` namespace is **global**, not per customer.

### Retrieve

Look up a transaction by id — primarily to learn its current status. Emits a `retrieve`
audit record.

```ruby
txn = client.transactions.retrieve("txn_123")
txn.status  # => "pending" / "succeeded" / "failed" / "cancelled"
```

An unknown id raises `BmlTokenization::NotFoundError`.

### List (pagination + filters)

Page-number pagination. `page` defaults to 1; `page_size` defaults to 20 and must not
exceed 100 (an over-cap `page_size` is rejected locally). Optional, combinable filters:
`customer_id` and `status` (an unrecognized `status` is rejected locally). Returns a
`BmlTokenization::TransactionList`. Not audited.

```ruby
page = client.transactions.list(
  page:        1,
  page_size:   20,
  customer_id: "cust_123",   # optional filter
  status:      "succeeded"   # optional filter; one of the four statuses
)

page.records      # => [BmlTokenization::Transaction, ...]
page.page         # => 1
page.page_size    # => 20
page.total_count  # => total matching, when the platform returns it
page.empty?       # => true when nothing matches

page.each { |txn| puts "#{txn.id}: #{txn.status}" }  # TransactionList is Enumerable
```

Listing when nothing matches, or requesting a page beyond the results, returns an **empty
page** — not an error.

## Tokenization resource

Convert a captured card into a masked, non-reversible **token**, look up a token's
current details, and revoke a token. Reached via `client.tokenization`. The only card
input accepted is a **single-use hosted-capture handle** — a raw PAN or CVV is never
accepted, returned, or logged, and there is deliberately **no detokenization / reveal-PAN
operation** of any kind. Every operation runs against the client's configured environment
and credentials, and emits a card-data-free audit record.

The returned `BmlTokenization::Token` exposes only masked fields — `reference`, `scheme`,
`last4`, `expiry_month`, `expiry_year`, `status` (plus the informational `environment`) —
and its `inspect`/`to_s`/`to_h` render nothing else.

### Tokenize

Issue a token from a single-use handle. Returns an `active` `Token`. Idempotent per account
+ environment: re-tokenizing the same card returns the **existing** token, never a
duplicate. A missing/blank handle — or an `actor` that looks like a card number — is
rejected locally before any remote call. Emits a `tokenize` audit record.

```ruby
token = client.tokenization.tokenize("single_use_handle_from_hosted_capture", actor: "user-42")

token.reference     # => "tok_9f3a…" (opaque, non-reversible; used by cards-on-file / transactions)
token.status        # => "active"
token.last4         # => "4242"
token.environment   # => :sandbox
```

### Retrieve

Look up a token's current masked details and validity status. An unknown reference raises
`BmlTokenization::NotFoundError`. Emits a `retrieve` audit record.

```ruby
token = client.tokenization.retrieve("tok_9f3a…")
token.status      # => "active" / "revoked" / "expired"
token.active?     # => true
```

### Revoke (permanent)

Permanently invalidate a token (terminal `revoked`; never reactivated). **No cascade** —
revoking does not delete or mutate any card-on-file or transaction record that references
the token; those references simply become unusable, and later use is rejected by the
consuming operation. An unknown reference raises `NotFoundError`; an already-revoked token
raises `ConflictError`. Emits a `revoke` audit record.

```ruby
token = client.tokenization.revoke("tok_9f3a…")
token.revoked?    # => true
```

## Errors

Every failure maps to a distinguishable subclass of `BmlTokenization::Error`:

| Class | Condition |
|-------|-----------|
| `ValidationError` | Missing/invalid field (local pre-remote or platform-reported), incl. bad amount, non-MVR currency, or over-cap page size. `#field` names the offender. |
| `NotFoundError` | Unknown customer, card reference, transaction id, or token reference (incl. a create against a non-existent customer, or retrieve/revoke of an unknown token). |
| `ConflictError` | Genuine conflict per platform rules — including a transaction `reference` reused with differing parameters, and revoking an already-revoked token (`#body` carries the existing record when the platform returns it). An already-on-file card, an identical transaction replay, and re-tokenizing the same card are normalized to an idempotent success, not an error. |
| `AuthenticationError` | Missing/invalid credentials or client configuration. |
| `ConfigurationError` | Setup problem detected before the request (e.g. non-TLS base URL). Subclass of `AuthenticationError`. |
| `RateLimitError` | Still rate-limited after the bounded retry budget. `#retry_after` carries the server hint. |
| `AvailabilityError` | Remote outage or timeout after bounded retry. No partial record is returned. |

## Testing

Deterministic suite (no credentials — HTTP is stubbed with WebMock):

```bash
bundle exec rspec spec/contract spec/unit
```

Opt-in sandbox integration suite (skips cleanly when credentials are absent):

```bash
# Customers
BML_ENV=sandbox BML_API_KEY=... BML_APP_ID=... \
  bundle exec rspec spec/integration/customers_sandbox_spec.rb

# Cards-on-file (also needs a single-use card handle)
BML_ENV=sandbox BML_API_KEY=... BML_APP_ID=... BML_CARD_HANDLE=... \
  bundle exec rspec spec/integration/cards_on_file_sandbox_spec.rb

# Transactions (needs an existing customer id; BML_CARD_REFERENCE enables the stored-card path)
BML_ENV=sandbox BML_API_KEY=... BML_APP_ID=... BML_CUSTOMER_ID=... \
  bundle exec rspec spec/integration/transactions_sandbox_spec.rb

# Tokenization (needs a single-use card handle; BML_APP_ID_ALT enables the cross-account
# isolation check, BML_PROD_API_KEY the environment-isolation check)
BML_ENV=sandbox BML_API_KEY=... BML_APP_ID=... BML_CARD_HANDLE=... \
  bundle exec rspec spec/integration/tokenize_sandbox_spec.rb \
                    spec/integration/retrieve_sandbox_spec.rb \
                    spec/integration/revoke_sandbox_spec.rb
```

The tokenization resource returns masked-only tokens and exposes **no** operation that
reveals a full card number.
