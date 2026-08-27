# Phase 1 Data Model: Card-on-File Endpoints

**Feature**: `002-card-on-file-endpoints` | **Date**: 2026-08-27

Derived from spec Key Entities + Functional Requirements. This library holds **no persistent state**;
these are in-memory value objects returned to the caller, the transient request inputs, and the audit
records emitted on state changes. The remote BML platform is the system of record for stored cards and
for the exact field set and duplicate rules (spec Assumptions, R4/R5).

## Entity: Card on File

The stored-card record returned by store, retrieve, and (as elements) list.

| Field | Type | Notes / Source |
|-------|------|----------------|
| `reference` | String (opaque) | Platform-assigned **safe reference** for the stored card (FR-002/FR-003). Primary identifier used for retrieve/remove. Read-only, non-sensitive; carries no exploitable relationship to the PAN (Principle I). |
| `customer_id` | String | The owning customer's identifier (FR-011). Ties the card to its owner. |
| `scheme` | String (optional) | Card scheme/brand from the masked summary (e.g. Visa, Mastercard). Mirrored from platform. |
| `last_four` | String (optional) | Last four digits of the PAN — the only PAN fragment ever exposed (FR-003). |
| `expiry_month` | Integer (optional) | Expiry month from the masked summary. |
| `expiry_year` | Integer (optional) | Expiry year from the masked summary. |
| `status` | String (optional) | Platform-provided validity/status when present (e.g. active/expired). |
| `expired?` | Boolean (derived) | Read-only convenience derived from `expiry_month`/`expiry_year` (and/or `status`) so expiry is discoverable (edge case, R4). Not new business logic — no payment decision is made here. |
| `created_at` | Timestamp (optional) | Platform-set creation time, if returned. Informational. |

**Forbidden fields (MUST NOT exist anywhere on this entity or its serialization):** full PAN, card
security code (CVV/CVV2), full track data, PIN, the single-use card handle, or any Sensitive
Authentication Data (FR-003, SC-002, Principle I). Only `last_four` (a masked fragment) is permitted.

**Representation rules**:

- The exact field set is mirrored from the platform response (R4); the fields above are the expected
  shape, not a library-defined canonical schema.
- Logging renders only the safe `reference`, `customer_id`, and outcome via the shared masking
  concern; the masked summary is not logged verbatim, and the handle/PAN/CVV are never logged (R12).

## Input value: Store Card Details (store input)

The inputs supplied on `store`. Never includes raw card data.

| Field | Type | Notes |
|-------|------|-------|
| `customer_id` | String (required) | The existing customer to associate the card with (FR-011). Validated present before any remote call. |
| `card_handle` | String (required) | The pre-tokenized, **single-use** card handle from hosted capture — the only card input accepted (FR-002, R3). Validated present before any remote call. |
| `actor` | String (optional) | Integrator-supplied actor reference recorded in the audit record when provided (FR-015, R10). Not card data. |

**Rules**:

- Presence + well-formedness of the required inputs — `customer_id` and `card_handle` — are validated
  before any remote call (FR-007); the platform enforces handle validity/expiry/consumption on top.
- The library **MUST NOT** accept a raw PAN or CVV on this or any operation (FR-002, FR-003).
- Storing a card the customer already has on file is **idempotent**: the existing `CardOnFile` is
  returned and no duplicate is created (FR-013, R5). Sameness is determined by the platform, not by
  local fingerprinting.
- A store for a non-existent customer fails with an error identifying the missing customer; no card is
  stored (edge case).

## Entity: Card on File List

A customer's cards on file returned for a single list request (FR-004, R11).

| Field | Type | Notes |
|-------|------|-------|
| `customer_id` | String | The customer whose cards these are. |
| `records` | Array<CardOnFile> | The customer's stored cards (possibly **empty**). |

**Rules** (R11):

- `list` returns **all** of the customer's cards on file; the set is small and bounded — **no
  pagination** is applied.
- Listing a customer with no stored cards → **empty** `records`, not an error (US2-2, edge case).
- Each element is a `CardOnFile` exposing only the safe reference + masked summary (FR-003).

## Entity: Audit Record (emitted on state change)

An immutable record emitted for each **state-changing** operation — `store` and `remove` — capturing
who/what/when/outcome without exposing card data (FR-006a, FR-015, R10). Reads (`list`, `retrieve`)
emit **no** audit record.

| Field | Type | Notes |
|-------|------|-------|
| `action` | String | `store` or `remove`. |
| `card_reference` | String | The safe reference of the affected card (never card data). |
| `actor` | String | **Who**: the configured client/API identity (e.g. App ID); includes the optional integrator-supplied actor reference when provided. |
| `occurred_at` | Timestamp | When the action occurred. |
| `outcome` | String | Result (e.g. success/failure), sufficient to reconstruct access (Principle IV). |

**Forbidden in an audit record**: full PAN, CVV, track data, PIN, the single-use handle, and the
masked summary — nothing beyond the safe `card_reference` (FR-006a, FR-015).

## Error conditions (mapped, distinguishable — FR-010)

| Condition | Trigger | Caller-visible |
|-----------|---------|----------------|
| Validation error | Missing/invalid `customer_id` or `card_handle` — pre-remote (FR-007) — or platform-reported invalid/consumed/expired handle | Names the offending input |
| Not-found error | Unknown card reference on retrieve/remove; unknown customer on store/list (US3-2, US4-2, edge case) | Distinct not-found |
| Conflict error | A genuinely conflicting platform state that is **not** an already-on-file duplicate (duplicate store is normalized to idempotent success, R5) | Distinct conflict |
| Authentication/config error | Missing/invalid client credentials (edge case) | Distinct auth/config |
| Rate-limit error | Still rate-limited after the bounded retry budget (FR-014, R7) | Distinct rate-limit |
| Availability/timeout error | Remote outage/timeout after bounded retry (FR-014, edge case) | Actionable; no partial record returned |

## Lifecycle & state transitions

- **Stored → Removed (permanent).** `remove` permanently deletes the card-on-file record; afterward it
  does not appear in the customer's list and retrieval returns not-found (FR-006, US4-1, SC-004). Only
  the removal **audit record** (no card data) is retained. There is no deactivate/reactivate state.
- **Expiry** is a property of a stored card (`status`/`expired?`), discoverable via retrieve/list; it
  does not change the record's existence and is not enforced by this feature (payment decisions belong
  to `003`, R4).

## Relationships

- A **Card on File** belongs to exactly one **Customer** (feature `001`); a customer may have zero or
  more cards on file (FR-011). A customer must exist before a card is stored for them (spec
  Dependencies); this feature references the customer but does not manage the customer record.
- A stored card's safe `reference` is later consumed by the **transactions** resource (`003`) to
  initiate a payment; **charging a stored card is out of scope here** (spec Assumptions).
- **Consent** capture/retention is out of scope; the library accepts and persists no consent artifact
  (spec Assumptions, Clarification 2026-08-17).
