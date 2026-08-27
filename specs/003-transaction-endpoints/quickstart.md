# Quickstart & Validation: Transaction Endpoints

**Feature**: `003-transaction-endpoints` | **Date**: 2026-08-27

A run/validation guide proving the create → retrieve → list flow works end-to-end across **both create
paths** and upholds the data-protection, idempotency-and-conflict, currency/amount, status, pagination,
environment-isolation, and auditability guarantees. Implementation details live in `tasks.md`
(Phase 2) and the code; this guide only runs and checks. See [data-model.md](./data-model.md) and
[contracts/](./contracts/) for field- and contract-level detail.

## Prerequisites

- Ruby 3.1+ and Bundler.
- The `bml_tokenization` gem checked out with its shared `Client`, `transport`, and `audit` concerns
  available, and the customer resource (`001`) present — a customer must exist before a transaction is
  created (spec Dependencies). The card-on-file resource (`002`) is needed only to exercise the
  stored-card charge path.
- **For deterministic tests**: no credentials needed (HTTP is stubbed with WebMock/fixtures); both
  create paths, idempotent replay, idempotency conflict, transient-failure, and pagination responses
  are simulated via stubs.
- **For the opt-in sandbox suite (FR-011)**: BML **sandbox** credentials (API key / App ID), an
  existing sandbox **customer id**, and — for the stored-card path — a card-on-file **safe reference**,
  supplied via environment variables and never committed (Constitution Security & Compliance).
  Example: `BML_ENV=sandbox`, `BML_API_KEY=…`, `BML_APP_ID=…`, `BML_CUSTOMER_ID=…`,
  `BML_CARD_REFERENCE=…`.

## Setup

```bash
bundle install
```

## Run the deterministic suite (no credentials)

```bash
bundle exec rspec spec/contract spec/unit
```

Expected: all contract + unit specs pass, including checks that assert **no full PAN/CVV appears in
any input, output, or log**, that the redirect path returns a `pending` transaction with a hosted
payment URL, that the stored-card path resolves server-side with no redirect, that an identical
create replay is idempotent while a differing-parameter reuse raises a **conflict**, that non-MVR
currency and bad amounts are rejected **before** any network call, that list pagination defaults to 20
and rejects a page size over 100, and that create/retrieve emit card-data-free audit records.

## Run the opt-in sandbox integration suite (credential-gated)

```bash
BML_ENV=sandbox BML_API_KEY=... BML_APP_ID=... BML_CUSTOMER_ID=... BML_CARD_REFERENCE=... \
  bundle exec rspec spec/integration/transactions_sandbox_spec.rb
```

Expected: skips cleanly if credentials are absent; otherwise exercises the real sandbox end-to-end
(create redirect-path → retrieve → list; and, when a card reference is provided, the stored-card
charge path).

## Validation scenarios (map to spec acceptance criteria)

| # | Scenario | Steps | Expected outcome | Spec ref |
|---|----------|-------|------------------|----------|
| V1 | Create (redirect path) | `create(customer_id:, amount:, currency: "MVR", reference:, return_url:)` with no card | `Transaction` with `id`, `status: pending`, and a hosted `payment_url` | US1-1, SC-001 |
| V2 | Create (stored-card path) | `create(..., card_reference:)` for one of the customer's cards | Charged server-side, **no** `payment_url`; `status` is `succeeded`/`failed` | US1-2 |
| V3 | Reject missing/invalid field pre-remote | `create` omitting a required field | Validation error **names** the field; **no** network call | US1-3, FR-005, SC-003 |
| V4 | Reject bad amount | `create` with zero / negative / non-integer `amount` | Validation error naming `amount`; no transaction, no remote call | FR-005b, edge case |
| V5 | Reject non-MVR currency | `create` with `currency: "USD"` | Validation error naming `currency`; no transaction, no remote call | FR-005c, edge case |
| V6 | Require return URL on redirect path | `create` without `card_reference` and without `return_url` | Validation error naming `return_url`; no remote call | FR-002, edge case |
| V7 | Non-existent customer | `create` with an unknown `customer_id` | Error identifies the missing customer; no transaction created | FR-005a, edge case |
| V8 | Environment isolation | Create in sandbox mode | Transaction created in sandbox, not visible in production | US1-4, FR-007, SC-006 |
| V9 | Idempotent replay | `create` twice with same `reference` and identical parameters | Second call returns the **existing** transaction; **0** duplicates, **0** extra charges | FR-013, SC-007 |
| V10 | Idempotency conflict | `create` reusing a `reference` with a different amount/customer/card | **Conflict** error naming the mismatch; no transaction, no charge | FR-013, SC-007 |
| V11 | Global reference scope | Reuse a `reference` under a **different** customer | Treated as the same key (replay or conflict), not a new transaction | FR-013 |
| V12 | Retrieve a transaction | `retrieve(id)` for a created transaction | Current record incl. `status` returned | US2-1 |
| V13 | Retrieve unknown | `retrieve(bogus)` | Not-found error | US2-2 |
| V14 | Pending distinguishable | Retrieve a redirect-path transaction before completion | `status` reads `pending`, distinct from terminal outcomes | FR-006, edge case |
| V15 | List a page | Create one+ transactions, then `list` | A page of transaction records returned | US3-1 |
| V16 | List pagination | Create more than one page; request a specific `page` | Only that page returned; default `page_size` is 20 | US3-2, FR-004 |
| V17 | Reject over-max page size | `list(page_size: 101)` | Validation error naming the page size; no over-large page | FR-004, edge case |
| V18 | Filter by customer | `list(customer_id:)` | Only that customer's transactions returned | US3-3 |
| V19 | Filter by status | `list(status: "succeeded")` | Only matching transactions; unknown status → validation error | US3-4 |
| V20 | Empty page | `list` when none match | **Empty** page (not an error) | US3-5, edge case |
| V21 | Page beyond results | `list(page: 9999)` | **Empty** page returned | Edge case |
| V22 | Transient failure retried | Stub 5xx/timeout then success | Call succeeds after bounded retry; create does not double-charge (idempotency key) | R2, edge case |
| V23 | Transient failure exhausted | Stub persistent 5xx/timeout | Distinguishable **availability** error; no partial record | FR-009, edge case |
| V24 | Misconfigured client | Call any op with missing/invalid credentials | Auth/config error (not a silent empty result) | FR-008, edge case |
| V25 | Audit on create/retrieve | Perform `create` and `retrieve`; inspect emitted audit records | Each emits who / what (op + id) / when / outcome; **no card data**, **no** payment URL | FR-012 |
| V26 | List not audited | Perform `list`; inspect audit output | **No** audit record emitted | FR-012, R11 |
| V27 | No PAN/CVV leakage | Perform each op; inspect outputs and logs | No full PAN or CVV in any input, error, log, or record; saved card only as safe reference | FR-010, SC-005 |

## Done / acceptance

The feature is validated when V1–V27 pass (deterministic suite green; sandbox suite green where
credentials are provided) and inspection confirms: an integrator can create and get a means to
complete payment on the first attempt with only documented fields (SC-001); all three operations are
demonstrable end-to-end against sandbox (SC-002); every invalid-input scenario names its offending
field (SC-003); the four statuses are unambiguously distinguishable (SC-004); no full PAN/CVV appears
anywhere (SC-005); sandbox/production isolation holds (SC-006); and a reused reference yields 0
duplicate transactions and 0 extra charges — returning the original on an identical replay and a
conflict on a differing one (SC-007).
