# Phase 1 Data Model: Customer API Endpoints

**Feature**: `001-customer-api-endpoints` | **Date**: 2026-08-18

Derived from spec Key Entities + Functional Requirements. This library holds **no persistent state**;
these are in-memory value objects returned to the caller and the transient request inputs. The remote
BML platform is the system of record for customer records and for the exact field set and uniqueness
rules (spec Assumptions, R3).

## Entity: Customer

The customer record returned by create, retrieve, and update.

| Field | Type | Notes / Source |
|-------|------|----------------|
| `id` | String (opaque) | Platform-assigned unique customer identifier (FR-002). Primary identifier used for retrieve/update. Read-only (server-assigned). |
| `first_name` | String (required) | Customer given name. Locally required (R3, 2026-08-23 clarification). |
| `last_name` | String (required) | Customer family name. Locally required (R3). |
| `email` | String (required) | Customer contact email. Locally required (R3). |
| `phone` | String (optional) | Customer contact phone. Optional locally; platform may still require it. |
| `reference` | String (optional) | Integrator-supplied reference for correlation with the integrator's own records. |
| `created_at` | Timestamp (optional) | Platform-set creation time, if returned. Informational. |
| `updated_at` | Timestamp (optional) | Platform-set last-update time, if returned. Informational. |

**Forbidden fields (MUST NOT exist anywhere on this entity or its serialization):** full PAN, card
security code (CVV/CVV2), full track data, PIN, or any Sensitive Authentication Data. This feature
manages the customer record only; payment instruments/tokens are out of scope (FR-010, spec
Assumptions).

**Representation rules**:

- The exact field set is mirrored from the platform response (R3); the fields above are the expected
  shape, not a library-defined canonical schema.
- Logging renders only non-sensitive fields via the shared masking concern; full records are not
  logged verbatim (R7).

## Input value: Customer Details (create/update input)

The mutable details supplied on create and update. Never includes card data.

| Field | Type | Notes |
|-------|------|-------|
| `first_name` | String (required) | Forwarded to the platform. Locally required (R3). |
| `last_name` | String (required) | Forwarded to the platform. Locally required (R3). |
| `email` | String (required) | Forwarded to the platform. Locally required (R3). |
| `phone` | String (optional) | Forwarded to the platform if present. |
| `reference` | String (optional) | Integrator correlation reference. |

**Rules**:

- Presence + well-formedness of the locally required fields — `first_name`, `last_name`, `email` —
  validated before any remote call (FR-006, R3); the platform enforces the full field/uniqueness
  contract on top.
- **Update uses full-replace semantics (FR-005, R9)**: the input represents the complete record, and
  any mutable field omitted is **cleared/reset** on the platform, not left unchanged. Because a full
  replace must be a complete valid record, the same required-field validation applies to update as to
  create. The platform-assigned `id` is never mutable.
- Invalid/missing required input fails with a validation error **naming the offending field** and
  makes **no** remote call (FR-006, US1-2, US4-2, SC-003).

## Entity: Customer List Page

A bounded subset of customer records returned for a single list request, plus the information needed
to request subsequent pages (FR-004, R4).

| Field | Type | Notes |
|-------|------|-------|
| `records` | Array<Customer> | The customers on this page (possibly empty). |
| `page` | Integer | The 1-based page number this page represents (echoed back). |
| `page_size` | Integer | Records-per-page in effect for this request (default 20, max 100). |
| `has_next` / `next_page` | Boolean / Integer (optional) | Whether a further page exists, and/or the next page number to request; absent/false on the final page. |

**Rules** (R4, 2026-08-23 clarification):

- Pagination is **page-number based**: callers pass `page` (1-based) and optional `page_size`.
- `page_size` **defaults to 20** and **must not exceed 100**; a request with `page_size > 100` fails
  with a validation error (naming `page_size`) before any remote call — it is not silently clamped.
- Listing when no customers exist → **empty** `records`, not an error (edge case).
- Requesting a page beyond available results → **empty** `records`, not an error (edge case).
- `has_next`/`next_page` indicates the final page so callers can terminate iteration explicitly.

## Error conditions (mapped, distinguishable — FR-009)

| Condition | Trigger | Caller-visible |
|-----------|---------|----------------|
| Validation error | Missing/invalid required field — pre-remote (FR-006) or platform-reported | Names the offending field |
| Not-found error | Unknown customer identifier on retrieve/update (US2-2) | Distinct not-found |
| Conflict error | Duplicate customer per platform uniqueness rules on create (edge case) | Distinct conflict/duplicate |
| Authentication/config error | Missing/invalid client credentials (edge case) | Distinct auth/config |
| Availability/timeout error | Remote outage/timeout | Actionable; no partial record returned (edge case) |

## Relationships

- A **Customer** may later be associated with payment instruments/tokens (`004`) and transactions
  (`003`); managing those associations is **out of scope** for this feature (spec Assumptions). This
  feature owns the customer record lifecycle (create/retrieve/list/update) only.
- **Delete** is out of scope unless later confirmed supported by the remote platform (spec
  Assumptions).
