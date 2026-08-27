# Quickstart & Validation: Card-on-File Endpoints

**Feature**: `002-card-on-file-endpoints` | **Date**: 2026-08-27

A run/validation guide proving the store → list → retrieve → remove flow works end-to-end and upholds
the data-protection, idempotency, permanent-removal, resilience, and auditability guarantees.
Implementation details live in `tasks.md` (Phase 2) and the code; this guide only runs and checks. See
[data-model.md](./data-model.md) and [contracts/](./contracts/) for field- and contract-level detail.

## Prerequisites

- Ruby 3.1+ and Bundler.
- The `bml_tokenization` gem checked out with its shared `Client` available and the customer resource
  (`001`) present — a customer must exist before a card is stored (spec Dependencies).
- **For deterministic tests**: no credentials needed (HTTP is stubbed with WebMock/fixtures);
  transient-failure, rate-limit, and idempotent-re-store responses are simulated via stubs.
- **For the opt-in sandbox suite (FR-012)**: BML **sandbox** credentials (API key / App ID) plus a
  hosted-capture **single-use card handle**, supplied via environment variables — never committed
  (Constitution Security & Compliance). Example: `BML_ENV=sandbox`, `BML_API_KEY=…`, `BML_APP_ID=…`,
  `BML_CARD_HANDLE=…`.

## Setup

```bash
bundle install
```

## Run the deterministic suite (no credentials)

```bash
bundle exec rspec spec/contract spec/unit
```

Expected: all contract + unit specs pass, including the checks that assert **no raw PAN/CVV appears in
any input, output, or log**, that an already-on-file re-store is idempotent, that a removed card is
gone, that transient failures are retried within the bounded budget, and that store/remove emit
card-data-free audit records while reads do not.

## Run the opt-in sandbox integration suite (credential-gated)

```bash
BML_ENV=sandbox BML_API_KEY=... BML_APP_ID=... BML_CARD_HANDLE=... \
  bundle exec rspec spec/integration/cards_on_file_sandbox_spec.rb
```

Expected: skips cleanly if credentials/handle are absent; otherwise exercises the real sandbox
end-to-end (store → list → retrieve → remove).

## Validation scenarios (map to spec acceptance criteria)

| # | Scenario | Steps | Expected outcome | Spec ref |
|---|----------|-------|------------------|----------|
| V1 | Store a card | `store(customer_id:, card_handle:)` with a valid single-use handle | Returns `CardOnFile` with a safe `reference` + masked summary; **no full card number** | US1-1, SC-001, SC-002 |
| V2 | Reject invalid handle | `store` with an invalid/consumed/expired handle | Error names the problem; **no** card stored | US1-2 |
| V3 | Reject missing required input pre-remote | `store` omitting `customer_id` or `card_handle` | Validation error **names** the input; **no** network call | FR-007, SC-006 |
| V4 | Store for non-existent customer | `store` with an unknown `customer_id` | Error identifies the missing customer; no card stored | Edge case |
| V5 | Environment isolation on store | Store in sandbox mode | Card stored in sandbox, not visible in production | US1-3, FR-008, SC-005 |
| V6 | Idempotent re-store | `store` the same card twice for the same customer | Second call returns the **existing** `CardOnFile`; **no duplicate** | FR-013, edge case |
| V7 | List a customer's cards | Store one+ cards, then `list(customer_id:)` | Each stored card returned with safe reference + masked summary | US2-1 |
| V8 | List when none exist | `list` for a customer with no cards | **Empty** list (not an error) | US2-2 |
| V9 | Retrieve a card | `retrieve(reference)` for a stored card | Current record (masked summary incl. expiry/validity) returned | US3-1 |
| V10 | Retrieve unknown | `retrieve(bogus)` | Not-found error | US3-2 |
| V11 | Remove a card (permanent) | `remove(reference)`, then retrieve + list | Card gone: retrieval returns not-found; absent from the list; not recoverable | US4-1, FR-006, SC-004 |
| V12 | Remove unknown/already-removed | `remove(bogus)` or remove twice | Not-found error; no other card affected | US4-2 |
| V13 | Expiry discoverable | Store/retrieve a card; inspect expiry/validity | Expiry month/year + validity status (and `expired?`) are exposed | Edge case, FR-003 |
| V14 | Transient failure retried | Stub 5xx/timeout then success | Call succeeds after bounded retry (≤2) within the timeout | FR-014, edge case |
| V15 | Transient failure exhausted | Stub persistent 5xx/timeout | Distinguishable **availability** error after retries; no partial record | FR-014, edge case |
| V16 | Rate-limit handled | Stub 429 with `Retry-After`, then success / persistent 429 | Retries honoring the hint; succeeds, or raises a distinguishable **rate-limit** error | FR-014, edge case |
| V17 | Misconfigured client | Call any op with missing/invalid credentials | Auth/config error (not a silent empty result) | Edge case, FR-009 |
| V18 | Audit on state change | Perform `store` and `remove`; inspect emitted audit records | Each emits who (client identity + optional actor) / reference / when / outcome; **no card data** | FR-006a, FR-015 |
| V19 | Reads not audited | Perform `list` and `retrieve`; inspect audit output | **No** audit record emitted | FR-015 |
| V20 | No SAD/PAN leakage | Perform each op; inspect outputs and logs | No full PAN, CVV, or single-use handle in any error, log, or record | FR-003, SC-002 |

## Done / acceptance

The feature is validated when V1–V20 pass (deterministic suite green; sandbox suite green where
credentials + a handle are provided) and inspection confirms: zero raw-card-data leakage across
outputs and logs (SC-002); all four operations demonstrable end-to-end against sandbox (SC-003);
removed cards are 0% present in subsequent lists and 100% not-found on retrieval (SC-004); environment
isolation holds (SC-005); and every invalid-input scenario names its offending input (SC-006).
