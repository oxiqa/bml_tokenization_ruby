# Contract: Public Library API — Customers Resource

**Feature**: `001-customer-api-endpoints` | **Consumers**: integrators embedding the `bml_tokenization`
gem who need to manage customer records.

The customer capability is exposed as a per-resource class reached through the existing configured
client, consistent with other resources (FR-001). Method names are illustrative of the contract shape;
the binding contract is the **inputs, outputs, and error conditions** below. Contract tests
(`spec/contract/customers_api_spec.rb`) MUST verify each row.

## Access

```text
client = BmlTokenization::Client.new(...)   # EXISTING — base URL, environment, credentials
client.customers                             # NEW — returns the Customers resource
```

The resource performs every operation against the environment and credentials configured on `client`
(FR-007, FR-008). No per-call credentials (FR-008).

## Operation: create

Register a new customer.

- **Input**: customer details — `first_name`, `last_name`, `email` (**required**, validated locally per
  R3), `phone` and `reference:` (optional). No card data accepted (FR-010).
- **Success output**: a `Customer` with the platform-assigned `id` plus the submitted details (FR-002).
- **Validation (pre-remote, no network call on failure — FR-006)**: missing/blank `first_name`,
  `last_name`, or `email` → validation error **naming the field**; no customer created (US1-2). The
  platform enforces any additional field rules on top.
- **Errors**: duplicate per platform uniqueness rules → conflict error (edge case); auth/config error;
  availability/timeout → actionable error, no partial record.
- **Environment**: created in the client's environment only; a sandbox customer is not created in
  production (US1-3, FR-007, SC-005).

## Operation: retrieve

Look up a single customer by identifier.

- **Input**: `id` (String, required).
- **Success output**: the current `Customer` record (FR-003).
- **Errors**: unknown identifier → not-found (US2-2); auth/config error.

## Operation: list

Browse customers with pagination.

- **Input**: `page` (1-based page number, optional — defaults to the first page) and `page_size`
  (optional — **defaults to 20**, **maximum 100**), per R4.
- **Success output**: a `CustomerListPage` — the page's `records` plus `page`, `page_size`, and
  whether a further page exists (FR-004).
- **Validation (pre-remote — FR-006)**: `page_size` greater than 100 → validation error **naming
  `page_size`**; no remote call.
- **Empty-page semantics**: no customers, or a page beyond available results → an **empty** page, not
  an error (edge cases).
- **Errors**: auth/config error; availability/timeout → actionable error.

## Operation: update

Replace a customer's mutable details (**full-replace semantics**, R9).

- **Input**: `id` (String, required) + the **complete** customer record (`first_name`, `last_name`,
  `email` required; `phone`, `reference` optional). Any mutable field omitted is **cleared/reset** on
  the platform, not left unchanged. The platform-assigned `id` is not mutable (FR-005).
- **Success output**: the updated `Customer`; subsequent retrieval reflects the change (US4-1).
- **Validation (pre-remote — FR-006)**: same required-field validation as create — missing/blank
  `first_name`, `last_name`, or `email`, or an invalid value → validation error **naming the field**;
  the customer is unchanged and no remote call is made (US4-2).
- **Errors**: unknown identifier → not-found; auth/config error.

## Cross-cutting guarantees (apply to every operation)

| Guarantee | Requirement |
|-----------|-------------|
| No SAD/PAN in inputs, outputs, or logs | FR-010, SC-004 |
| Required-field validation before any remote call, naming the field | FR-006, SC-003 |
| Environment isolation (no cross-environment access) | FR-007, SC-005 |
| Credentials from the client; none required per call | FR-008 |
| Distinguishable, actionable mapped errors | FR-009 |
| Independently testable against sandbox | FR-011, SC-002 |

## Explicitly NOT in this contract

- **No delete-customer operation** (out of scope unless the platform later confirms support — spec
  Assumptions).
- **No payment-instrument / token management** (attach/list/remove tokens) — separate concern, out of
  scope (spec Assumptions). Tokenization is feature `004`.
- **No card-data input** on any operation (FR-010).
