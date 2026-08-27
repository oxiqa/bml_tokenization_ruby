# Contract: Public Library API — CardsOnFile Resource

**Feature**: `002-card-on-file-endpoints` | **Consumers**: integrators embedding the `bml_tokenization`
gem who need to store and manage customers' saved payment cards.

The card-on-file capability is exposed as a per-resource class reached through the existing configured
client, consistent with other resources (FR-001). Method names are illustrative of the contract shape;
the binding contract is the **inputs, outputs, and error conditions** below. Contract tests
(`spec/contract/cards_on_file_api_spec.rb`) MUST verify each row.

## Access

```text
client = BmlTokenization::Client.new(...)   # EXISTING — base URL, environment, credentials
client.cards_on_file                         # NEW — returns the CardsOnFile resource
```

The resource performs every operation against the environment and credentials configured on `client`
(FR-008, FR-009). No per-call credentials (FR-009). Every operation runs within the client's
configurable request timeout and applies the shared bounded-retry policy (FR-014; see Cross-cutting).

## Operation: store

Save a customer's card for reuse.

- **Input**: `customer_id` (String, **required**) and `card_handle` (String, **required**) — a
  pre-tokenized, **single-use** card handle from hosted capture. Optional `actor:` (String) recorded
  in the audit record. **No raw PAN or CVV is ever accepted** (FR-002, FR-003).
- **Success output**: a `CardOnFile` with the platform-assigned safe `reference` and masked summary
  (scheme, last four, expiry) — **never** a full card number (FR-002, FR-003).
- **Idempotency**: storing a card the customer already has on file returns the **existing**
  `CardOnFile` and creates **no** duplicate (FR-013); sameness is determined by the platform (R5).
- **Validation (pre-remote, no network call on failure — FR-007)**: missing/blank `customer_id` or
  `card_handle` → validation error **naming the input**; no card stored. An invalid/consumed/expired
  handle reported by the platform → validation error (US1-2).
- **Audit**: emits a `store` audit record (who = client identity + optional `actor`, which
  `reference`, when, outcome) with **no card data** (FR-015).
- **Errors**: non-existent customer → error identifying the missing customer, no card stored (edge
  case); auth/config error; rate-limit/availability → actionable error after bounded retry.
- **Environment**: stored in the client's environment only; a sandbox card is not visible in
  production (US1-3, FR-008, SC-005).

## Operation: list

Enumerate a customer's cards on file.

- **Input**: `customer_id` (String, **required**).
- **Success output**: a `CardOnFileList` — **all** of the customer's stored cards, each a `CardOnFile`
  with safe reference + masked summary (FR-004). **No pagination** (R11).
- **Empty semantics**: a customer with no stored cards → an **empty** list, not an error (US2-2).
- **Errors**: auth/config error; rate-limit/availability → actionable error.
- **Not audited** (read operation, FR-015).

## Operation: retrieve

Look up a single card on file by its safe reference.

- **Input**: `reference` (String, **required**).
- **Success output**: the current `CardOnFile` (masked summary only, incl. expiry/validity) (FR-005).
- **Errors**: unknown reference → not-found (US3-2); auth/config error.
- **Not audited** (read operation, FR-015).

## Operation: remove

Permanently delete a saved card.

- **Input**: `reference` (String, **required**). Optional `actor:` (String) recorded in the audit
  record.
- **Behavior**: **permanently deletes** the card-on-file record (not deactivation); afterward the card
  does not appear in the customer's list and retrieval returns not-found (FR-006, US4-1, SC-004). The
  card is not retrievable or recoverable.
- **Success output**: confirmation of removal (no card data returned).
- **Audit**: emits a `remove` audit record (who = client identity + optional `actor`, which
  `reference`, when, outcome) with **no card data** (FR-006a, FR-015).
- **Errors**: reference already removed or never existed → not-found; no other card affected (US4-2);
  auth/config error.

## Cross-cutting guarantees (apply to every operation)

| Guarantee | Requirement |
|-----------|-------------|
| No raw PAN/CVV accepted; no SAD/PAN in inputs, outputs, or logs | FR-002, FR-003, SC-002 |
| Required-input validation before any remote call, naming the input | FR-007, SC-006 |
| Environment isolation (no cross-environment access) | FR-008, SC-005 |
| Credentials from the client; none required per call | FR-009 |
| Distinguishable, actionable mapped errors (incl. rate-limit, availability) | FR-010, FR-014 |
| Configurable timeout + bounded auto-retry (≤2, backoff) on transient failures; rate-limit honors retry-after | FR-014 |
| State-changing ops (store, remove) emit an audit record with no card data; reads are not audited | FR-006a, FR-015 |
| Independently testable against sandbox | FR-012, SC-003 |

## Explicitly NOT in this contract

- **No raw-card-data input** on any operation — only a single-use handle for store (FR-002, FR-003).
- **No charge/payment initiation** using a stored card — handled by the transactions resource (`003`),
  which references the card-on-file safe reference (spec Assumptions).
- **No update of stored-card metadata** and **no "default card"** selection (out of scope unless later
  confirmed — spec Assumptions).
- **No consent capture/retention** — the integrator obtains consent upstream; the library accepts no
  consent artifact (spec Assumptions).
- **No pagination** on list — a customer's card set is small and bounded (R11).
