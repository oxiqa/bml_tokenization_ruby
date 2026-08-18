# Phase 1 Data Model: Tokenization Endpoints

**Feature**: `004-tokenization-endpoints` | **Date**: 2026-08-17

Derived from spec Key Entities + Functional Requirements. This library holds **no persistent state**;
these are in-memory value objects returned to the caller and the transient request inputs. The remote
BML platform is the system of record.

## Entity: Token

The masked, non-reversible representation of a stored card, returned by tokenize and retrieve.

| Field | Type | Notes / Source |
|-------|------|----------------|
| `reference` | String (opaque) | Platform-assigned safe token reference; non-sequential, non-reversible (FR-006). Primary identifier used by downstream resources (`002`, `003`). |
| `scheme` | String | Card scheme/brand (e.g. `visa`, `mastercard`) — part of masked summary (FR-003). |
| `last4` | String (4 digits) | Last four digits of the card — masked summary only. |
| `expiry_month` | Integer (1–12) | Card expiry month. |
| `expiry_year` | Integer (4-digit) | Card expiry year. |
| `status` | Enum: `active` \| `revoked` \| `expired` | Validity status (FR-004). |
| `account_scope` | String (opaque) | Identifies the owning merchant/app account (for reasoning about idempotency scope; never a secret). |
| `environment` | Enum: `sandbox` \| `production` | Environment the token belongs to (FR-008). Informational; sourced from client config. |

**Forbidden fields (MUST NOT exist anywhere on this entity or its serialization):** full PAN, card
security code (CVV/CVV2), full track data, PIN. (FR-003, FR-006a, FR-013.)

**Representation rules**:

- `inspect` / `to_s` / `to_h` / JSON output MUST render only the fields above (all masked). Overridden
  to prevent accidental leakage (R7).
- No method returns or reconstructs the full card number (FR-006a).

### State transitions (Token.status)

```text
        tokenize
  (none) ─────────▶ active
                      │
        revoke        │ card/token expiry (platform-driven)
    ┌─────────────────┼───────────────────────┐
    ▼                 ▼                        ▼
 revoked           revoked                  expired
 (terminal)     (terminal)              (terminal for use;
                                         still retrievable, reports status)
```

- `active → revoked`: via `revoke` (FR-005). Terminal; never reactivated (FR-005). Idempotent-ish:
  revoking an already-revoked token yields a not-found/already-revoked error (US3 scenario 2).
- `active → expired`: platform-driven when the underlying card expires. The library reports it; it does
  not transition tokens itself.
- Any non-`active` status → use in a downstream operation is **rejected** by the consuming operation
  (FR-005a, edge case "revoked or expired token is used").

## Input value: Card Handle (input-only, never persisted)

Single-use handle from a hosted capture step; the only accepted card input for tokenize (FR-002, R3).

| Field | Type | Notes |
|-------|------|-------|
| `handle` | String (opaque, single-use) | Produced by hosted fields / SDK; consumed by tokenize. Not persisted, not logged, not returned. |

**Rules**: Presence + well-formedness validated locally before any remote call (FR-007). Invalid,
already-consumed, or expired handles fail without issuing a token (US1 scenario 2). Never stored,
cached, or written to logs/audit (FR-013).

## Input value: Actor Reference (optional, audit only)

Optional integrator-supplied identifier enriching the audit "who" (FR-012a, R8).

| Field | Type | Notes |
|-------|------|-------|
| `actor` | String (optional) | Operator/end-user reference. Recorded in the audit record alongside the account identity. MUST NOT contain SAD or cardholder data (validated/rejected if it looks like a PAN). Optional on every call. |

## Record: Audit Entry (emitted, not returned to caller)

One per tokenize / retrieve / revoke (FR-012).

| Field | Type | Notes |
|-------|------|-------|
| `operation` | Enum: `tokenize` \| `retrieve` \| `revoke` | Which action. |
| `account` | String | The configured account/app identity — default "who". |
| `actor` | String (optional) | Optional integrator-supplied actor, if provided. |
| `token_reference` | String (optional) | Affected token reference (absent/added once known). |
| `occurred_at` | Timestamp | When the operation happened. |
| `outcome` | Enum: `success` \| `failure` (+ error condition) | Result sufficient to reconstruct access. |

**Forbidden in audit:** PAN, CVV, SAD, the card handle value (FR-012, FR-013).

## Error conditions (mapped, distinguishable — FR-010)

| Condition | Trigger | Caller-visible |
|-----------|---------|----------------|
| Validation error | Missing/invalid input (bad handle, PAN-looking actor) — pre-remote (FR-007) | Names the offending input |
| Not-found error | Unknown token reference on retrieve/revoke (US2/US3) | Distinct not-found |
| Already-revoked | Revoke of an already-revoked token (US3 scenario 2) | Distinct (not-found/already-revoked) |
| Authentication/config error | Missing/invalid client credentials | Distinct auth/config |
| Conflict error | Platform conflict surfaced | Distinct conflict |
| Availability/timeout error | Remote outage/timeout during tokenize | Actionable; no partial/raw data left behind (edge case) |

## Relationships

- A **Token** is referenced (by `reference`) by **Card-on-File** records (`002`) and **Transactions**
  (`003`). This feature owns token issuance/lifecycle only; those resources own their own records.
- Revoking a Token does **not** cascade to those references (FR-005a); they become unusable, not
  deleted.
