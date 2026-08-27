# Contract: Public Library API — Transactions Resource

**Feature**: `003-transaction-endpoints` | **Consumers**: integrators embedding the `bml_tokenization`
gem who need to initiate and track payments on the Bank of Maldives platform.

The transaction capability is exposed as a per-resource class reached through the existing configured
client, consistent with other resources (FR-001). Method names are illustrative of the contract shape;
the binding contract is the **inputs, outputs, and error conditions** below. Contract tests
(`spec/contract/transactions_api_spec.rb`) MUST verify each row.

## Access

```text
client = BmlTokenization::Client.new(...)   # EXISTING — base URL, environment, credentials
client.transactions                          # NEW — returns the Transactions resource
```

The resource performs every operation against the environment and credentials configured on `client`
(FR-007, FR-008). No per-call credentials (FR-008). Every operation runs within the client's
configurable request timeout and applies the shared bounded-retry policy (R2; see Cross-cutting).

## Operation: create

Initiate a payment for an existing customer. Selects a completion path by whether a stored card is
supplied.

- **Input**:
  - `customer_id` (String, **required**) — an existing customer (FR-005a).
  - `amount` (Integer, **required**) — positive integer in **MVR minor units** (FR-005b).
  - `currency` (String, **required**) — must be `"MVR"` (FR-005c).
  - `reference` (String, **required**) — integrator idempotency key, globally unique (FR-013).
  - `return_url` (String, **required for the redirect path**) — where to return the customer's browser;
    rejected-if-missing when no `card_reference` is given; ignored for the stored-card path (FR-002).
  - `card_reference` (String, optional) — a **card-on-file safe reference**; its presence selects the
    server-side charge path. **No raw PAN or CVV is ever accepted** (FR-010).
  - `actor` (String, optional) — recorded in the audit record.
- **Success output (redirect path — no `card_reference`)**: a `Transaction` with a platform-assigned
  `id`, status `pending`, and a **hosted `payment_url`** to direct the customer to (FR-002).
- **Success output (stored-card path — with `card_reference`)**: a `Transaction` charged server-side
  with **no** `payment_url`, whose `status` reflects the resolved outcome (`succeeded`/`failed`)
  directly (FR-002).
- **Idempotency (FR-013, SC-007)**: a repeated `reference` with **identical** material parameters
  (amount, currency, customer, card) returns the **existing** `Transaction` and initiates **no** second
  charge. A repeated `reference` with **any differing** material parameter raises a **conflict** error
  naming the mismatch and creates nothing. The `reference` namespace is **global** (not per customer).
- **Validation (pre-remote, no network call on failure — FR-005)**: missing/blank required field →
  validation error **naming the field**; non-integer/zero/negative `amount` → validation error naming
  `amount` (FR-005b); `currency` other than `"MVR"` → validation error naming `currency` (FR-005c);
  missing `return_url` on the redirect path → validation error naming `return_url` (FR-002).
- **Audit**: emits a `create` audit record (who = client identity + optional `actor`, what = `create` +
  `id`/`reference`, when, outcome) with **no card data** and **not** the payment URL (FR-012).
- **Errors**: non-existent customer → error identifying the missing customer, no transaction created
  (FR-005a, edge case); auth/config error; rate-limit/availability → actionable error after bounded
  retry.
- **Environment**: created in the client's environment only; a sandbox transaction is not visible in
  production (US1-4, FR-007, SC-006).

## Operation: retrieve

Look up a single transaction by its identifier — primarily to learn its status.

- **Input**: `id` (String, **required**). Optional `actor:` (String) recorded in the audit record.
- **Success output**: the current `Transaction`, including its `status` (one of `pending`,
  `succeeded`, `failed`, `cancelled`) and details (FR-003, FR-006).
- **Audit**: emits a `retrieve` audit record (who/what/when/outcome, no card data) (FR-012).
- **Errors**: unknown `id` → not-found (US2-2); auth/config error; availability error after retry.

## Operation: list

Enumerate transactions with pagination and optional filters.

- **Input**:
  - `page` (Integer, optional) — 1-based; a page beyond the results returns an **empty page** (US3-2,
    US3-5).
  - `page_size` (Integer, optional) — defaults to **20**; MUST NOT exceed **100** — an over-max value
    is **rejected** with a clear error (FR-004, R7).
  - `customer_id` (String, optional) — filter to one customer (US3-3). Combinable with `status`.
  - `status` (String, optional) — one of `pending`/`succeeded`/`failed`/`cancelled`; an unrecognized
    value is a **validation error** naming the filter (US3-4, FR-004). Combinable with `customer_id`.
- **Success output**: a `TransactionList` page — the matching `Transaction` records plus pagination
  metadata (`page`, `page_size`, and `total_count` when the platform returns it) (FR-004).
- **Empty semantics**: no transactions (or none matching the filters) → an **empty** page, not an
  error (US3-5).
- **Errors**: over-max `page_size` → validation error; unrecognized `status` → validation error;
  auth/config error; availability error after retry.
- **Not audited** (read operation not named in FR-012's create/retrieve scope; R11).

## Cross-cutting guarantees (apply to every operation)

| Guarantee | Requirement |
|-----------|-------------|
| No raw PAN/CVV accepted; no SAD/PAN in inputs, outputs, or logs; saved card only by safe reference | FR-010, SC-005 |
| Required-input validation before any remote call, naming the field (incl. amount, currency, return URL) | FR-005, FR-005a–c, SC-003 |
| Idempotent create on a global reference; conflict on reused reference with differing parameters | FR-013, SC-007 |
| Four distinguishable statuses: pending / succeeded / failed / cancelled | FR-006, SC-004 |
| Page-number pagination (default 20, max 100; over-max rejected); optional combinable customer/status filters | FR-004 |
| Environment isolation (no cross-environment access) | FR-007, SC-006 |
| Credentials from the client; none required per call | FR-008 |
| Distinguishable, actionable mapped errors (validation, not-found, conflict, auth, availability) | FR-009 |
| Configurable timeout + bounded auto-retry on transient failures (safe for create via the idempotency key) | R2 |
| Create and retrieve emit an audit record with no card data (and not the payment URL); list is not audited | FR-012 |
| Independently testable against sandbox | FR-011, SC-002 |

## Explicitly NOT in this contract

- **No raw-card-data input** on any operation — a saved card is used only via its safe reference
  (FR-010); new-card capture happens in the platform's hosted flow.
- **No refund, void/cancel, or capture** of a transaction (out of scope unless later confirmed — spec
  Assumptions).
- **No webhook/callback handling** — integrators determine outcome by `retrieve`; the return URL is an
  input to create, not a callback the library handles (spec Assumptions).
- **No guest/anonymous payments** — every transaction references an existing customer (FR-005a).
- **No multi-currency** — MVR only (FR-005c).
