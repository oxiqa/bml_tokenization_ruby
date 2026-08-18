# Contract: Public Library API — Tokenization Resource

**Feature**: `004-tokenization-endpoints` | **Consumers**: integrators embedding the `bml_tokenization`
gem, and the sibling card-on-file (`002`) / transaction (`003`) resources.

The tokenization capability is exposed as a per-resource class reached through the existing configured
client, consistent with other resources (FR-001). Method names are illustrative of the contract shape;
the binding contract is the **inputs, outputs, masking guarantees, and error conditions** below.
Contract tests (`spec/contract/tokenization_api_spec.rb`) MUST verify each row.

## Access

```text
client = BmlTokenization::Client.new(...)   # EXISTING — base URL, environment, credentials
client.tokenization                          # NEW — returns the Tokenization resource
```

The resource performs every operation against the environment and credentials configured on `client`
(FR-008, FR-009). No per-call credentials (FR-009).

## Operation: tokenize

Issue a token for a captured card.

- **Input**:
  - `card_handle` (String, required) — single-use hosted-capture handle. Raw PAN/CVV MUST be rejected
    by the type of this input; only a handle is accepted (FR-002, R3).
  - `actor:` (String, optional) — audit actor reference (FR-012a).
- **Success output**: a `Token` (status `active`) with `reference`, `scheme`, `last4`,
  `expiry_month`, `expiry_year` — masked only, no full PAN/CVV (FR-003).
- **Idempotency**: same underlying card within the same account + environment returns the **existing**
  token; no duplicate token issued (FR-011). Different account/environment → distinct token.
- **Validation (pre-remote, no network call on failure — FR-007)**: missing/blank handle → validation
  error naming the field; an `actor` that looks like a PAN → rejected.
- **Errors**: invalid/consumed/expired handle → error, no token issued (US1-2); auth/config error;
  availability/timeout → actionable error, nothing raw retained (edge case).
- **Audit**: one `tokenize` record (account [+ actor], resulting token reference, outcome) — no card
  data (FR-012).

## Operation: retrieve

Look up a token's current masked details.

- **Input**: `reference` (String, required); `actor:` (optional).
- **Success output**: a `Token` with masked summary + `status` (`active`/`revoked`/`expired`) only
  (FR-004). No full PAN/CVV (FR-003).
- **Errors**: unknown reference → not-found (US2-2); auth/config error.
- **Audit**: one `retrieve` record.

## Operation: revoke

Permanently invalidate a token.

- **Input**: `reference` (String, required); `actor:` (optional).
- **Success output**: confirmation that the token is `revoked` (terminal). Permanent; never reactivated
  (FR-005).
- **No cascade**: MUST NOT delete/mutate card-on-file or transaction records that reference the token
  (FR-005a). Those references remain but any later use is rejected by the consuming operation.
- **Errors**: unknown or already-revoked reference → not-found/already-revoked (US3-2); auth/config
  error.
- **Audit**: one `revoke` record.

## Cross-cutting guarantees (apply to every operation)

| Guarantee | Requirement |
|-----------|-------------|
| Masked-only output; no operation returns the full PAN | FR-003, FR-006a |
| No SAD/PAN persisted, logged, or left in memory beyond the call | FR-013 |
| Non-sequential, non-reversible token values | FR-006 |
| Environment + account isolation | FR-008, FR-011 |
| Distinguishable, actionable mapped errors | FR-010 |
| Audit record per operation, no card data | FR-012, FR-012a |
| Independently testable against sandbox | FR-014 |

## Explicitly NOT in this contract

- **No detokenize / reveal-PAN operation** of any kind (FR-006a, Clarification Q1).
- **No list-tokens operation** (out of scope; enumeration is card-on-file's concern — see spec
  Assumptions).
- **No raw-card-number input** on any operation (Clarification Q4).
