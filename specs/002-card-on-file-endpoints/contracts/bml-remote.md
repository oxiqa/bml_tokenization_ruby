# Contract: BML Remote HTTP — Cards on File

**Feature**: `002-card-on-file-endpoints` | **Boundary**: `bml_tokenization` gem ⇄ Bank of Maldives
tokenization / Connect platform.

This documents the remote request/response shapes the library depends on (Constitution Principle III:
every external interface has a documented, versioned contract with contract tests). Exact paths/field
names are owned by the remote platform; the library mirrors that contract rather than defining its own
(spec Assumptions, R4/R5). Contract tests (`spec/contract/cards_on_file_remote_spec.rb`) stub these
shapes with WebMock so conformance — including retry and rate-limit behavior — is verified
deterministically, without live credentials.

## Common

- **Transport**: HTTPS only (TLS). Base URL and environment (sandbox/production) come from the client
  config; the same code path serves both without change (Principle III, FR-008).
- **Auth**: credentials (API key / App ID) injected by the existing client on every request (FR-009).
  Never logged.
- **Encoding**: JSON request/response bodies.
- **Timeout & retry**: each request runs within the client's configurable timeout; transient failures
  (connection error, timeout, 5xx, or 429) are retried up to **2** times with backoff, honoring a
  `Retry-After` header when present (FR-014, R6/R7). Non-transient responses are not retried.
- **Never sent by the library**: full PAN, CVV/CVV2, PIN, track data, or any SAD — `store` sends only
  the single-use card handle (FR-002, FR-003).

## Endpoint: store card on file

- **Request** (representative — associates a single-use handle with a customer):

  ```json
  { "customer_id": "<opaque-customer-id>", "card_handle": "<single-use-handle>" }
  ```

- **Success response** (representative — masked summary only, never a full PAN):

  ```json
  {
    "reference": "<opaque-card-reference>",
    "customer_id": "<opaque-customer-id>",
    "scheme": "visa",
    "last_four": "4242",
    "expiry_month": 12,
    "expiry_year": 2028,
    "status": "active",
    "created_at": "2026-08-27T00:00:00Z"
  }
  ```

- **Idempotent re-store**: if the same underlying card is already on file, the platform returns the
  **existing** record (whether via a 200 "exists", a 201, or a conflict response carrying the existing
  reference). The library normalizes all of these to a successful return of the existing `CardOnFile`
  — no duplicate, no error surfaced to the caller (FR-013, R5).
- **Error responses to map**: invalid/consumed/expired handle or missing field → validation; unknown
  customer → not-found/validation identifying the customer; auth failure → auth; 429 → rate-limit
  (after retry); timeout/5xx → availability (after retry).

## Endpoint: list cards on file (by customer)

- **Request**: customer identifier in path/query. No pagination parameters (R11).
- **Success response** (representative):

  ```json
  {
    "data": [
      { "reference": "…", "customer_id": "…", "scheme": "visa", "last_four": "4242", "expiry_month": 12, "expiry_year": 2028, "status": "active" }
    ]
  }
  ```

- **Empty results**: `data` is an empty array with no error when the customer has no stored cards
  (US2-2).
- **Error responses to map**: auth failure → auth; 429 → rate-limit; timeout/5xx → availability.

## Endpoint: retrieve card on file

- **Request**: card safe reference in path/query.
- **Success response**: the current card record (masked summary as above).
- **Error responses to map**: unknown reference → not-found; auth failure → auth.

## Endpoint: remove card on file

- **Request**: card safe reference in path/query; a delete operation.
- **Success response**: a success acknowledgement (no card data in the body).
- **Behavior**: the card is **permanently deleted** — subsequent retrieve returns not-found and it no
  longer appears in the customer's list (FR-006, SC-004).
- **Error responses to map**: unknown/already-removed reference → not-found; auth failure → auth.

## Response → library mapping (all endpoints)

| Remote signal | Library behavior |
|---------------|------------------|
| 2xx with card JSON | Build `CardOnFile` value object |
| 2xx/201/conflict indicating already-on-file | Normalize to `CardOnFile` for the existing card (idempotent success — FR-013) |
| 2xx with list JSON | Build `CardOnFileList`; empty `data` → empty list |
| 2xx delete acknowledgement | Return removal confirmation; emit `remove` audit record |
| Validation error (4xx) | Raise mapped validation error naming the input (FR-010) |
| Not-found (404) | Raise mapped not-found error (FR-010) |
| Conflict (409) not representing an existing-card duplicate | Raise mapped conflict error (FR-010) |
| Auth failure (401/403) | Raise mapped auth/config error (FR-010) |
| Rate-limited (429) | Retry with backoff honoring `Retry-After`; if still limited, raise mapped rate-limit error (FR-014) |
| Timeout / 5xx | Retry up to 2×; if still failing, raise mapped availability error; return no partial record (FR-014, edge case) |

## Contract-test obligations

- Assert requests carry auth headers and **never** any raw card data, single-use handle beyond the
  store request body, or SAD in logs.
- Assert `store` sends only the handle + customer association and the response is mapped to a
  `CardOnFile` with **no full PAN** (only `last_four`).
- Assert an already-on-file re-store is normalized to an idempotent success returning the existing
  reference (no duplicate, no error) (FR-013).
- Assert a transient failure (5xx/timeout/connection error) is retried up to 2× and then either
  succeeds or raises a distinguishable availability error (FR-014).
- Assert a 429 is retried honoring `Retry-After` and, if still limited, raises a distinguishable
  rate-limit error (FR-014).
- Assert `store` and `remove` emit an audit record (who/what/when/outcome) with **no card data beyond
  the safe reference**, and that `list`/`retrieve` emit **no** audit record (FR-006a, FR-015).
- Assert a removed card is not retrievable (not-found) and absent from the customer's list (SC-004).
- Assert every mapped error condition above is distinguishable by type.
- Assert environment selection routes to the configured base URL and never crosses environments.
