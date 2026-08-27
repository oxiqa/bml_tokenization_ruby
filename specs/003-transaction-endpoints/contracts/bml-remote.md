# Contract: Remote BML HTTP — Transactions

**Feature**: `003-transaction-endpoints` | **Counterparty**: the Bank of Maldives Connect platform.

This documents the **remote HTTP request/response contract** the `Transactions` resource conforms to.
The platform is the source of truth for exact paths, field names, amount limits, and duplicate rules
(spec Assumptions); the shapes below are the expected contract the library maps to and from, verified
by stubbed contract tests (`spec/contract/transactions_remote_spec.rb` with WebMock/fixtures) and by
the opt-in sandbox suite. All requests are JSON over **TLS**, use the client's base URL for the
selected environment, and carry the client's configured authentication (API key / App ID) — never
per-call credentials (FR-007, FR-008).

Field names below are illustrative of the mapped contract; the binding requirement is the **mapping**
(library field ↔ remote field), the **error-condition mapping**, and the **invariants**, not the exact
JSON spelling, which is mirrored from the platform.

## Common

- **Auth**: client-configured credentials in request headers; a missing/invalid credential →
  `401/403` → mapped to an **authentication/configuration** error (FR-009).
- **Transport resilience**: timeout + bounded automatic retry (≤2, backoff) on connection
  errors/`5xx`/timeout; `429` honored per any `Retry-After` (R2). Exhausted transient failure → an
  **availability** error; no partial record is returned.
- **Amount/currency**: `amount` is an integer in **MVR minor units**; `currency` is `"MVR"`. Both are
  validated locally before the request is sent (FR-005b/FR-005c) — the request is never made when they
  are malformed.
- **No cardholder data**: requests carry **no** PAN/CVV; a saved card is referenced only by its safe
  `card_reference` (FR-010).

## Create — `POST /transactions`

Two request shapes on one endpoint, selected by presence of `card_reference`.

**Request (redirect path — no stored card):**

```json
{
  "reference": "order-8842",
  "customer_id": "cus_123",
  "amount": 15000,
  "currency": "MVR",
  "return_url": "https://merchant.example/return"
}
```

**Request (stored-card path):**

```json
{
  "reference": "order-8843",
  "customer_id": "cus_123",
  "amount": 15000,
  "currency": "MVR",
  "card_reference": "cof_safe_abc"
}
```

**Response (redirect path) — `201`:**

```json
{
  "id": "txn_ABC123",
  "reference": "order-8842",
  "customer_id": "cus_123",
  "amount": 15000,
  "currency": "MVR",
  "status": "pending",
  "payment_url": "https://connect.bml.example/pay/txn_ABC123",
  "created_at": "2026-08-27T10:00:00Z"
}
```

**Response (stored-card path) — `201`:** same shape with `status` resolved to `succeeded` or `failed`
and **no** `payment_url`.

**Mapping & invariants:**

| Remote → Library | Notes |
|------------------|-------|
| `status` (raw) → `Transaction#status` | Normalized to the four canonical values `pending`/`succeeded`/`failed`/`cancelled` (R6). |
| `payment_url` present ⇔ redirect path | Present only when no `card_reference` was sent (R3). Treated as a completion secret — not logged (R11). |
| `id` → `Transaction#id` | Platform-assigned identifier used for retrieve. |

**Idempotency & conflict (FR-013, R8):**

- The library treats `reference` as a **global** idempotency key. A duplicate `reference` with the
  **same** material parameters MUST resolve to the **existing** transaction (no second charge) — whether
  the platform returns the original record or a duplicate signal, the library normalizes to "return the
  existing transaction".
- A duplicate `reference` with **differing** material parameters (amount/currency/customer/card) MUST
  surface as a **conflict** error (mapped from the platform's conflict/`409` response, or detected by
  comparison against the existing transaction) — no new transaction, no charge.

**Error mapping:**

| Remote | Library error |
|--------|---------------|
| `400` invalid field / unsupported value | **validation** (names the field) |
| `404` unknown customer | **not-found / missing customer** (no transaction created) |
| `409` duplicate reference with differing parameters | **conflict** (names the mismatch) |
| `401/403` | **authentication/configuration** |
| `429` / `5xx` / timeout (after bounded retry) | **availability** |

## Retrieve — `GET /transactions/{id}`

**Response — `200`:** a transaction record (same shape as create's response for the matching path;
`payment_url` present only for an unresolved redirect-path transaction).

| Remote | Library error |
|--------|---------------|
| `200` | `Transaction` with normalized `status` |
| `404` | **not-found** |
| `401/403` | **authentication/configuration** |
| `429`/`5xx`/timeout (after retry) | **availability** |

## List — `GET /transactions?page={n}&page_size={s}&customer_id={c}&status={st}`

- `page_size` defaults to **20** and is capped at **100**; the library **rejects** an over-max
  `page_size` **before** sending the request (R7). `page`, `customer_id`, and `status` are optional;
  `status` is validated locally against the four canonical values before sending (R6).

**Response — `200`:**

```json
{
  "records": [ { "id": "txn_ABC123", "reference": "order-8842", "status": "pending", "amount": 15000, "currency": "MVR", "customer_id": "cus_123" } ],
  "page": 1,
  "page_size": 20,
  "total_count": 1
}
```

| Remote | Library result / error |
|--------|------------------------|
| `200` (including zero records) | `TransactionList` page (empty page is **not** an error) |
| `400` unrecognized filter | **validation** (names the filter) — where not already caught locally |
| `401/403` | **authentication/configuration** |
| `429`/`5xx`/timeout (after retry) | **availability** |

## Environment isolation

Sandbox and production are distinct base URLs/credentials selected on the client; a transaction created
in one environment is never visible in the other (FR-007, SC-006). Contract tests assert requests go
to the environment configured on the client.
