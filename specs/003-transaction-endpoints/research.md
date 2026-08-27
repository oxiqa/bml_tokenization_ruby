# Phase 0 Research: Transaction Endpoints

**Feature**: `003-transaction-endpoints` | **Date**: 2026-08-27

The specification has **no** `[NEEDS CLARIFICATION]` markers; its requirements checklist passes and
eight behavioral decisions were fixed during `/speckit-clarify` (2026-08-17 and 2026-08-27 sessions):
two create paths (hosted redirect vs stored-card server-side charge); customer always required
(no guests); amount as a positive integer in minor units; idempotent create on the integrator
reference; paginated list with optional customer/status filters; **MVR-only** currency; **four
distinct statuses**; **page-number pagination** (default 20, max 100); **idempotency conflict** on a
reused reference with differing parameters; a **global** reference namespace; and a **return URL
required for the redirect flow only**. The remaining open items are implementation-context choices
(language, transport, retry safety for a charging call, status/amount representation, pagination
shape, error mapping) and how to satisfy the security/observability principles. Each is resolved below.

## R1. Implementation language & packaging

- **Decision**: Ruby, packaged as a gem; the transaction capability is a new resource class on the
  existing client, mirroring customers (`001`) and cards on file (`002`).
- **Rationale**: The project is named `bml_tokenization` (Ruby snake_case); the spec's Assumptions
  model the library on the sibling `bml-connect-ruby` gem "where a configured client object exposes
  per-resource classes"; features `001`/`002`/`004` already committed the library to this Ruby-gem
  structure. Any other choice would fragment the library.
- **Alternatives considered**: A separate service (rejected — the spec is a client-side integration
  library); a different language (rejected — no basis in project conventions).

## R2. HTTP transport & retry safety for a charging call

- **Decision**: Use Ruby standard library `net/http` + `json`; reuse the existing shared `Client` and
  the shared `transport` concern (TLS, environment selection, auth headers, configurable request
  timeout, bounded automatic retry ≤2 with backoff) introduced by `002`. Add no new runtime
  dependency. Automatic retry is applied to create as well as retrieve/list.
- **Rationale**: Constitution Principle V requires justifying every dependency; transaction
  request/response shapes are simple JSON over HTTPS. Retry is safe for create **because the global
  integrator reference is the idempotency key** (R8): a retried or re-sent create with the same
  reference and parameters returns the existing transaction and initiates **no** second charge
  (FR-013, SC-007). This is exactly the property that makes automatic retry safe for a money-moving
  call.
- **Alternatives considered**: `faraday`/`httparty` (rejected — extra dependencies for no functional
  gain); disabling retry on create (rejected — the idempotency key already prevents double charge, and
  transient-failure resilience is valuable); a custom socket layer (rejected — reinvents TLS/HTTP
  unsafely).

## R3. Two create paths (hosted redirect vs stored-card charge)

- **Decision**: A single `create` operation selects the path by whether a **card-on-file safe
  reference** is supplied. Without one, the platform returns a **hosted payment URL** and the initial
  status is `pending`; the caller must supply a **return/redirect URL** (required for this path). With
  a safe reference, the platform performs a **server-side charge** and returns a resolved status
  (`succeeded`/`failed`) with no payment URL and no redirect.
- **Rationale**: Spec FR-002 and the 2026-08-17 clarification define both paths on the same operation;
  the return URL is required only for the browser-completed path (2026-08-27 clarification, FR-002).
  One operation with an explicit branch keeps the API uniform and the branch explicit (Principle V).
- **Alternatives considered**: Two separate operations (`create_hosted` / `charge_saved_card`)
  (rejected — the spec models one create resource; a single operation with a clear branch is simpler
  and matches the platform's single create endpoint); making the return URL always required (rejected
  — the clarification scoped it to the redirect path only).

## R4. Amount representation

- **Decision**: The amount is a **positive integer in the currency's smallest (minor) unit** (e.g.
  `15000` = MVR 150.00). The library rejects non-integer, zero, or negative amounts locally, before
  any remote call, with an error naming the amount field.
- **Rationale**: Spec FR-005b and the 2026-08-17 clarification. Integer minor units avoid
  floating-point rounding errors in money handling; local validation upholds "fail before remote call"
  (FR-005) and gives a precise, testable error.
- **Alternatives considered**: Decimal/major-unit amounts (rejected by clarification — rounding risk
  and ambiguity); deferring amount validation to the platform (rejected — FR-005 requires pre-remote
  validation of well-formedness).

## R5. Currency validation (MVR only)

- **Decision**: The library accepts **only MVR** and rejects any other currency locally, before any
  remote call, with a validation error naming the currency field.
- **Rationale**: 2026-08-27 clarification and FR-005c. This resolves the earlier tension between FR-005
  ("validate a supported currency") and the Assumptions ("platform is source of truth for supported
  currencies"): currency is the one field the library constrains locally rather than deferring to the
  platform. MVR is the Bank of Maldives primary settlement currency; constraining it avoids a false
  multi-currency contract the platform may not honor (YAGNI, Principle V).
- **Alternatives considered**: Format-only validation + platform authority (rejected by clarification);
  a fixed multi-currency allowlist (rejected by clarification — MVR only). If BML later confirms
  additional currencies, this is a localized, additive change to one validation rule.

## R6. Status representation (four distinct values)

- **Decision**: Expose exactly four canonical statuses — `pending` (in progress/unresolved),
  `succeeded`, `failed` (declined/errored), `cancelled` (customer-abandoned) — normalizing the
  platform's raw status vocabulary onto this set. The same four values are the accepted `status`
  filter values on list.
- **Rationale**: 2026-08-27 clarification and FR-006. A fixed, distinguishable set lets integrators
  drive order fulfilment/reconciliation deterministically and lets the list filter validate an
  unknown status locally (FR-004). Distinguishing `cancelled` from `failed` supports reconciliation of
  abandoned vs declined payments.
- **Alternatives considered**: Three statuses folding cancelled into failed (rejected by
  clarification); mirroring the platform's raw status strings verbatim (rejected — leaves the set
  undefined and the filter un-validatable).

## R7. Pagination shape (page-number, default 20 / max 100)

- **Decision**: List uses **page-number pagination**, exposing a `page` number and a `page_size`.
  `page_size` defaults to 20 and MUST NOT exceed 100; a requested `page_size` > 100 is rejected with a
  clear error. A page beyond the available results returns an **empty page**, not an error.
- **Rationale**: 2026-08-27 clarification and FR-004; identical to the customer resource (`001`) so the
  library's list contract is uniform across resources. Optional `customer_id` and `status` filters are
  combinable; an unrecognized `status` filter is a local validation error.
- **Alternatives considered**: Cursor/opaque-token pagination (rejected by clarification — diverges
  from the customer/card resources and complicates "request page N beyond results"); clamping an
  over-max page size silently (rejected — the customer resource rejects it, and explicit rejection is
  clearer than a silent clamp).

## R8. Idempotency & conflict semantics (global reference)

- **Decision**: The **integrator-supplied reference is the idempotency key** and is unique **across all
  transactions** (a global namespace, not per customer). On create: (a) if no transaction has the
  reference, create it; (b) if one exists and the new request's **material parameters** (amount,
  currency, customer, and card reference if any) are **identical**, return the existing transaction
  with **no** second charge; (c) if one exists but any material parameter **differs**, raise a
  **conflict** error naming the mismatch and create nothing. The library normalizes the platform's raw
  duplicate response to this outcome.
- **Rationale**: 2026-08-27 clarifications and FR-013/SC-007. Matching-payload replay makes retries and
  at-least-once client delivery safe (no double charge); differing-payload rejection catches an
  integrator bug where a reference was accidentally reused for a different charge, rather than silently
  charging the wrong thing (the constitution's "no hidden fallbacks that weaken a control", Principle
  V). A global namespace is the simplest single idempotency-key space.
- **Alternatives considered**: Return-original-and-ignore-diff (rejected by clarification — masks a
  client bug); treat-diff-as-new-transaction (rejected — contradicts FR-013); per-customer scope
  (rejected by clarification — a second namespace to reason about).

## R9. Return/redirect URL requirement

- **Decision**: A customer **return/redirect URL is required** for the new-card hosted-redirect path
  and the library rejects a create call locally (no remote call) if it is missing; it is **not
  required and is ignored** for the stored-card server-side charge path.
- **Rationale**: 2026-08-27 clarification and FR-002. The return URL is only meaningful when the
  customer completes payment in a browser; requiring it for the server-side path would force a
  meaningless value. Local rejection upholds "fail before remote call" (FR-005) with a precise error.
- **Alternatives considered**: Always required (rejected by clarification); always optional with a
  platform default (rejected by clarification — depends on a platform default existing).

## R10. Error mapping

- **Decision**: Map remote and local failures onto the shared, distinguishable error hierarchy:
  **validation** (missing/invalid field, bad amount, non-MVR currency, missing return URL, unknown
  status filter, over-max page size), **not-found** (unknown transaction id / unknown customer),
  **conflict** (idempotency-key reuse with differing parameters), **authentication/configuration**
  (missing/invalid credentials), and **availability** (timeout/5xx/rate-limit after bounded retry).
  Each carries actionable context and names the offending field where applicable.
- **Rationale**: Spec FR-009 requires distinguishable, actionable errors by condition; reusing the
  shared `errors` hierarchy keeps error handling uniform across resources (Principle IV).
- **Alternatives considered**: A single generic error (rejected — FR-009 requires distinguishability);
  resource-local error classes (rejected — duplicates the shared hierarchy).

## R11. Security & observability posture

- **Decision**: No operation accepts, returns, logs, or persists a full PAN or CVV; a saved card is
  referenced **only** by its card-on-file safe reference (FR-010). Structured logs render only
  non-sensitive fields (transaction id, integrator reference, customer id, status, outcome) via the
  shared masking concern; the hosted payment URL is treated as sensitive and is not logged verbatim.
  **Create and retrieve** emit an audit record (who = client/API identity + optional integrator-supplied
  actor reference; what = operation + transaction id; when; outcome) with no card data (FR-012). List
  (a read) follows the spec's FR-012 scope, which names create and retrieve.
- **Rationale**: Constitution Principles I and IV; spec FR-010/FR-012, SC-005. The library stays out of
  the cardholder-data environment entirely — new-card capture is the platform's hosted concern.
- **Alternatives considered**: Logging the payment URL for debuggability (rejected — it is a
  completion secret); auditing list as well (not required by FR-012; omitted for YAGNI, revisit if a
  compliance need appears).

## R12. Environment & credentials

- **Decision**: Every operation runs against the environment (sandbox/production) and credentials
  configured on the client, never crossing environments and never requiring per-call credentials.
- **Rationale**: Spec FR-007/FR-008 and Constitution III (sandbox/prod selectable without code change);
  reuses the existing client configuration.
- **Alternatives considered**: Per-call environment/credentials (rejected — contradicts the shared
  client model and FR-008).

## Resolved unknowns

All Technical Context items are decided; **no `NEEDS CLARIFICATION` remain**. Language/transport (R1,
R2), create-path branching (R3), amount/currency (R4, R5), status (R6), pagination (R7), idempotency +
conflict (R8), return URL (R9), error mapping (R10), security/observability (R11), and environment
(R12) are all fixed by the spec, its clarifications, and the constitution.
