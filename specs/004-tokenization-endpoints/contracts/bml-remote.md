# Contract: BML Remote HTTP — Tokenization

**Feature**: `004-tokenization-endpoints` | **Boundary**: `bml_tokenization` gem ⇄ Bank of Maldives
tokenization / Connect platform.

This documents the remote request/response shapes the library depends on (Constitution Principle III:
every external interface has a documented, versioned contract with contract tests). Exact paths/field
names are owned by the remote platform; the library mirrors that contract rather than defining its own
(spec Assumptions). Contract tests (`spec/contract/bml_remote_spec.rb`) stub these shapes with WebMock
so conformance is verified deterministically, without live credentials.

## Common

- **Transport**: HTTPS only (TLS). Base URL and environment (sandbox/production) come from the client
  config; the same code path serves both without change (Principle III).
- **Auth**: credentials (API key / App ID) injected by the existing client on every request (FR-009).
  Never logged.
- **Encoding**: JSON request/response bodies.
- **Never sent by the library**: full PAN, CVV/CVV2, PIN, track data. The only card-bearing input is
  the single-use handle (FR-002, FR-013).

## Endpoint: create token (tokenize)

- **Request** (representative):

  ```json
  { "card_handle": "<single-use-handle>" }
  ```

- **Success response** (representative — masked only):

  ```json
  {
    "token_reference": "<opaque>",
    "scheme": "visa",
    "last4": "4242",
    "expiry_month": 12,
    "expiry_year": 2028,
    "status": "active"
  }
  ```

- **Idempotent duplicate**: when the same card was already tokenized for this account+environment, the
  platform (or the library's normalization) yields the **existing** token, not a new one (FR-011). The
  library MUST normalize whatever the platform returns to an idempotent outcome.
- **Error responses to map**: invalid/consumed/expired handle → validation; auth failure → auth;
  timeout/5xx → availability (surfaced as actionable, nothing raw retained).

## Endpoint: get token (retrieve)

- **Request**: token reference in path/query.
- **Success response**: masked summary + `status` (as above). MUST NOT contain a full PAN/CVV.
- **Error responses to map**: unknown reference → not-found; auth failure → auth.

## Endpoint: revoke token

- **Request**: token reference in path/query (+ revoke verb/endpoint per platform).
- **Success response**: token now `revoked` (terminal).
- **No cascade** on the platform side is not assumed by the library; the library performs no additional
  calls to mutate other resources (FR-005a).
- **Error responses to map**: unknown/already-revoked → not-found/already-revoked; auth failure → auth.

## Response → library mapping (all endpoints)

| Remote signal | Library behavior |
|---------------|------------------|
| 2xx with masked token JSON | Build `Token` value object (masked fields only) |
| Duplicate-of-existing card | Return existing `Token` (idempotent, FR-011) |
| Validation error (4xx) | Raise mapped validation error naming the field (FR-010) |
| Not-found (404) | Raise mapped not-found error (FR-010) |
| Conflict | Raise mapped conflict error (FR-010) |
| Auth failure (401/403) | Raise mapped auth/config error (FR-010) |
| Timeout / 5xx | Raise mapped availability error; retain no partial/raw data (edge case) |

## Contract-test obligations

- Assert requests carry auth headers and **never** a PAN/CVV/handle-in-log.
- Assert every mapped error condition above is distinguishable by type.
- Assert the parsed `Token` exposes only masked fields (no PAN/CVV present in any field or in
  `inspect`/`to_s`/serialization).
- Assert environment selection routes to the configured base URL and never crosses environments.
