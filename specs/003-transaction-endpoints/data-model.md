# Phase 1 Data Model: Transaction Endpoints

**Feature**: `003-transaction-endpoints` | **Date**: 2026-08-27

Derived from spec Key Entities + Functional Requirements. This library holds **no persistent state**;
these are in-memory value objects returned to the caller, the transient request inputs, and the audit
records emitted on create/retrieve. The remote BML platform is the system of record for transactions
and for the exact field set, amount limits, and uniqueness rules (spec Assumptions, R5/R8).

## Entity: Transaction

The payment record returned by create and retrieve, and as elements of a list page.

| Field | Type | Notes / Source |
|-------|------|----------------|
| `id` | String (opaque) | Platform-assigned unique transaction identifier (FR-002/FR-003). Primary identifier used for retrieve. Read-only, non-sensitive. |
| `reference` | String | Integrator-supplied reference for correlation; the **global idempotency key** (FR-013, R8). Unique across all transactions. |
| `customer_id` | String | The paying customer's identifier; **required** for every transaction (FR-005a). Ties the payment to an existing customer. |
| `amount` | Integer | Positive integer in the currency's **minor unit** (e.g. `15000` = MVR 150.00) (FR-005b, R4). |
| `currency` | String | Always `"MVR"` (FR-005c, R5). |
| `status` | String (enum) | One of `pending`, `succeeded`, `failed`, `cancelled` (FR-006, R6). Normalized from the platform's raw status. |
| `payment_url` | String (optional) | Hosted payment URL for the **redirect path** only (present when no stored card was supplied; absent for the server-side charge path) (FR-002, R3). Treated as a completion secret — not logged verbatim (R11). |
| `card_reference` | String (optional) | The card-on-file **safe reference** charged, for the **stored-card path** only (FR-010). Never a full PAN/CVV. |
| `return_url` | String (optional) | The integrator return/redirect URL supplied for the redirect path; echoed if the platform returns it. Required input for the redirect path only (FR-002, R9). |
| `created_at` | Timestamp (optional) | Platform-set creation time, if returned. Informational. |

**Forbidden fields (MUST NOT exist anywhere on this entity or its serialization):** full PAN, card
security code (CVV/CVV2), full track data, PIN, or any Sensitive Authentication Data (FR-010, SC-005,
Principle I). A saved card appears only as `card_reference` (a safe reference).

**Representation rules**:

- The exact field set is mirrored from the platform response (spec Assumptions); the fields above are
  the expected shape, not a library-defined canonical schema — except `status` (normalized to the four
  canonical values, R6) and `currency`/`amount` (constrained locally, R4/R5).
- Exactly one of `payment_url` (redirect path) or `card_reference` (stored-card path) characterizes a
  created transaction's completion route (R3).
- Logging renders only `id`, `reference`, `customer_id`, `status`, and outcome via the shared masking
  concern; `payment_url` is not logged verbatim, and PAN/CVV are never present to log (R11).

## Input value: Create Transaction Details (create input)

The inputs supplied on `create`. Never includes raw card data.

| Field | Required? | Notes |
|-------|-----------|-------|
| `customer_id` | **Required** | Must reference an existing customer; a missing/unknown customer fails without creating a transaction (FR-005a). |
| `amount` | **Required** | Positive integer, minor units; non-integer/zero/negative rejected pre-remote naming the field (FR-005b). |
| `currency` | **Required** | Must be `"MVR"`; any other value rejected pre-remote naming the field (FR-005c). |
| `reference` | **Required** | Integrator idempotency key; drives replay/conflict (FR-013). |
| `return_url` | **Conditionally required** | Required for the redirect path (no `card_reference`); rejected-if-missing pre-remote. Ignored for the stored-card path (FR-002, R9). |
| `card_reference` | Optional | A card-on-file safe reference; its presence selects the server-side charge path (FR-002, FR-010, R3). |
| `actor` | Optional | Integrator-supplied actor reference recorded in the audit record ("who", R11). |

**Validation order (all pre-remote — no network call on failure, FR-005):** presence of required
fields → `amount` integer/positive → `currency == "MVR"` → `return_url` present when no
`card_reference` → then the remote call. Each failure names the offending field.

## Input value: List Query (list input)

| Field | Required? | Notes |
|-------|-----------|-------|
| `page` | Optional | 1-based page number (default first page). A page beyond the results yields an empty page, not an error (FR-004). |
| `page_size` | Optional | Defaults to **20**; MUST NOT exceed **100** — an over-max value is rejected with a clear error (FR-004, R7). |
| `customer_id` | Optional | Filter to one customer's transactions (FR-004). Combinable with `status`. |
| `status` | Optional | One of `pending`/`succeeded`/`failed`/`cancelled`; an unrecognized value is a validation error naming the filter (FR-004, R6). Combinable with `customer_id`. |

## Entity: Transaction List Page

A bounded page of transactions returned by list, plus the metadata to request further pages.

| Field | Type | Notes |
|-------|------|-------|
| `records` | Array<Transaction> | The transactions on this page (possibly empty) (FR-004). |
| `page` | Integer | The 1-based page number returned. |
| `page_size` | Integer | Effective page size (≤ 100; default 20) (R7). |
| `total_count` | Integer (optional) | Total matching transactions, if the platform returns it; supports "request subsequent pages". |

**Empty semantics**: no transactions (or none matching the filters) → an **empty page**, not an error
(US3-5, FR-004).

## Entity: Audit Record (emitted, not stored by this library)

Emitted on **create** and **retrieve** (FR-012). A structured event, carrying no card data.

| Field | Notes |
|-------|-------|
| `who` | Client/API identity from the configured client, plus the optional integrator-supplied `actor`. |
| `what` | Operation (`create` / `retrieve`) and the transaction `id` (and `reference` for create). |
| `when` | Timestamp of the operation. |
| `outcome` | Success or the mapped error condition (validation/not-found/conflict/auth/availability). |

**Forbidden in audit records:** full PAN, CVV, track data, PIN, or the hosted payment URL — only the
safe transaction id / integrator reference / customer id and outcome (FR-012, Principle IV). List (a
read) is not audited under FR-012's stated scope (R11).

## State transitions (Transaction status)

The platform owns authorization/settlement; the library observes and normalizes status (R6). No
transition is initiated by this library beyond create.

```text
create (redirect path)      → pending ──► succeeded
                                      ├──► failed
                                      └──► cancelled   (customer abandons the hosted flow)

create (stored-card path)   → succeeded | failed   (resolved server-side, no pending redirect)
```

Retrieve reflects the current status; a still-in-progress payment reads `pending`, distinguishable
from the three terminal outcomes (FR-006, edge case).
