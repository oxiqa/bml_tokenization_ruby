# Contract: BML Remote HTTP — Customers

**Feature**: `001-customer-api-endpoints` | **Boundary**: `bml_tokenization` gem ⇄ Bank of Maldives
tokenization / Connect platform.

This documents the remote request/response shapes the library depends on (Constitution Principle III:
every external interface has a documented, versioned contract with contract tests). Exact paths/field
names are owned by the remote platform; the library mirrors that contract rather than defining its own
(spec Assumptions, R3). Contract tests (`spec/contract/customers_remote_spec.rb`) stub these shapes
with WebMock so conformance is verified deterministically, without live credentials.

## Common

- **Transport**: HTTPS only (TLS). Base URL and environment (sandbox/production) come from the client
  config; the same code path serves both without change (Principle III, FR-007).
- **Auth**: credentials (API key / App ID) injected by the existing client on every request (FR-008).
  Never logged.
- **Encoding**: JSON request/response bodies.
- **Never sent by the library**: full PAN, CVV/CVV2, PIN, track data, or any SAD — this resource
  carries customer contact data only (FR-010).

## Endpoint: create customer

- **Request** (representative — `first_name`, `last_name`, `email` required; `phone`, `reference`
  optional):

  ```json
  { "first_name": "Aisha", "last_name": "Ali", "email": "aisha@example.mv", "phone": "+9607777777", "reference": "acct-42" }
  ```

- **Success response** (representative):

  ```json
  {
    "id": "<opaque-customer-id>",
    "first_name": "Aisha",
    "last_name": "Ali",
    "email": "aisha@example.mv",
    "phone": "+9607777777",
    "reference": "acct-42",
    "created_at": "2026-08-18T00:00:00Z"
  }
  ```

- **Error responses to map**: missing/invalid field → validation; duplicate per uniqueness rules →
  conflict; auth failure → auth; timeout/5xx → availability.

## Endpoint: get customer (retrieve)

- **Request**: customer identifier in path/query.
- **Success response**: the current customer record (as above).
- **Error responses to map**: unknown identifier → not-found; auth failure → auth.

## Endpoint: list customers

- **Request**: page-number pagination — `page` (1-based) and `page_size` (default 20, max 100).
- **Success response** (representative):

  ```json
  {
    "data": [ { "id": "…", "first_name": "…", "last_name": "…", "email": "…", "phone": "…" } ],
    "page": 1,
    "page_size": 20,
    "has_next": false
  }
  ```

- **Empty results**: `data` is an empty array with no error, both when none exist and when a page
  beyond the results is requested (edge cases).
- **Over-cap page size**: the library rejects `page_size > 100` locally (validation error) before this
  request is ever sent.
- **Error responses to map**: auth failure → auth; timeout/5xx → availability.

## Endpoint: update customer

- **Request**: customer identifier in path/query + the **complete** customer record (full-replace
  semantics, R9) — same field shape as create. Fields omitted from the body are cleared/reset by the
  platform.
- **Success response**: the updated customer record.
- **Error responses to map**: unknown identifier → not-found; missing/invalid required field →
  validation; auth failure → auth.

## Response → library mapping (all endpoints)

| Remote signal | Library behavior |
|---------------|------------------|
| 2xx with customer JSON | Build `Customer` value object |
| 2xx with list JSON | Build `CustomerListPage` (records + next-page info); empty `data` → empty page |
| Validation error (4xx) | Raise mapped validation error naming the field (FR-009) |
| Not-found (404) | Raise mapped not-found error (FR-009) |
| Conflict/duplicate (409) | Raise mapped conflict error (FR-009) |
| Auth failure (401/403) | Raise mapped auth/config error (FR-009) |
| Timeout / 5xx | Raise mapped availability error; return no partial record (edge case) |

## Contract-test obligations

- Assert requests carry auth headers and **never** any card data or SAD in the body or logs.
- Assert every mapped error condition above is distinguishable by type.
- Assert an empty `data` array yields an empty `CustomerListPage` (not an error) for both
  no-customers and page-beyond-results.
- Assert environment selection routes to the configured base URL and never crosses environments.
