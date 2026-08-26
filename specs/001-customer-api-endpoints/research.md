# Phase 0 Research: Customer API Endpoints

**Feature**: `001-customer-api-endpoints` | **Date**: 2026-08-18

The specification has **no** `[NEEDS CLARIFICATION]` markers; its requirements checklist passes and
two scope decisions (delete deferred; payment-instrument management excluded) were resolved by
informed default and recorded in the spec's Assumptions. No spec-level unknowns remained for research.
The open items were implementation-context choices (language, transport, testing, pagination, error
mapping, and how to satisfy the security/observability principles). Each is resolved below.

## R1. Implementation language & packaging

- **Decision**: Ruby, packaged as a gem; the customer capability is a new resource class on the
  existing client.
- **Rationale**: The project is named `bml_tokenization` (Ruby snake_case), the feature request was
  "create class to handle customer related API endpoints", and the spec's Assumptions model the
  library on the sibling **`bml-connect-ruby`** gem, "where a configured client object exposes
  per-resource classes (such as transactions)." The sibling feature `004-tokenization-endpoints`
  already committed the library to this Ruby-gem structure. Choosing anything else would contradict
  the stated project structure and fragment the library.
- **Alternatives considered**: A separate service/microservice (rejected — the spec is explicitly a
  client-side integration library, not a service); a different language (rejected — no basis in the
  project conventions).

## R2. HTTP transport

- **Decision**: Use Ruby standard library `net/http` + `json`; reuse the existing shared `Client` for
  base URL, environment selection, TLS, and authentication headers. Add no new runtime dependency.
- **Rationale**: Constitution Principle V (Simplicity) requires justifying every dependency; customer
  request/response shapes are simple JSON over HTTPS. `bml-connect-ruby` and the sibling `004` feature
  use stdlib transport, keeping the dependency and supply-chain surface minimal (Security &
  Compliance: "known-vulnerable dependencies MUST be remediated"). Fewer deps = smaller attack
  surface.
- **Alternatives considered**: `faraday`/`httparty` (rejected — extra dependencies and indirection for
  no functional gain); a custom socket layer (rejected — reinvents TLS/HTTP unsafely).

## R3. Customer field contract (source of truth) & local required set

- **Decision**: The remote BML platform owns the full set of customer fields and uniqueness rules;
  the library mirrors that contract rather than defining its own. **As an exception (per the
  2026-08-23 clarification), the library enforces a minimal local required-field set — `email`,
  `first_name`, `last_name` — before any remote call.** `phone` and the integrator-supplied
  `reference` are optional locally. The platform may enforce additional required/format rules on top,
  which are surfaced per FR-009.
- **Rationale**: Spec Assumptions make the platform the source of truth, but FR-006 requires
  fail-fast local validation of required inputs. A minimal locally-enforced set (contact email + full
  name) gives a useful pre-remote check without duplicating the platform's full schema (Principle V),
  and keeps SC-003 (every required field names its offending value) verifiable. The platform still
  owns everything beyond this minimal set.
- **Alternatives considered**: Library-defined canonical customer schema (rejected — drifts from the
  platform, adds maintenance and a false source of truth); no local validation at all (rejected —
  FR-006 requires pre-remote validation); requiring `phone` too (rejected — the clarification made
  phone optional).

## R4. Pagination model

- **Decision** (per the 2026-08-23 clarification): List uses **page-number pagination** exposing a
  `page` number and a `page_size`. `page_size` **defaults to 20** and is **capped at 100**; a request
  above the cap is rejected with a validation error (chosen over silent clamping so the caller's
  intent is never quietly changed — the behavior is documented in FR-004 and the contracts). List
  returns a `CustomerListPage` value object carrying the page's records plus the `page`/`page_size`
  echoed back and whether a further page exists. Requesting a page beyond available results, or
  listing when none exist, yields an **empty page**, never an error (edge cases).
- **Rationale**: Spec US3 + edge cases require paginated results with empty-page semantics; the
  clarification fixed page-number paging with predictable, bounded page sizes so payloads stay
  manageable and tests are deterministic. Modeling the page as an explicit value object keeps
  pagination explicit over implicit (Principle V). Rejecting an over-cap `page_size` (vs clamping) is
  the more explicit, less surprising behavior (Principle V: explicit over implicit).
- **Alternatives considered**: Cursor/token-based pagination (rejected — the clarification chose
  page-number, and the "page beyond results" edge case assumes page numbers); page-number only with a
  fixed server size (rejected — the clarification requires a caller-controllable `page_size`);
  clamping an over-cap size instead of rejecting (rejected — silently altering caller intent is less
  explicit); returning a bare array and losing paging info (rejected — forces the caller to
  reconstruct pagination state).

## R5. Environment & credential handling

- **Decision**: Every operation runs against the environment (sandbox/production) and credentials
  configured on the shared `Client`; no per-call credentials, no cross-environment access.
- **Rationale**: Spec FR-007/FR-008 and Assumptions require reusing the existing client config;
  Principle III requires sandbox/prod be selectable without code change. Reusing the client keeps a
  single, tested auth/env path.
- **Alternatives considered**: Per-call credential arguments (rejected — FR-008 forbids requiring
  per-call credentials; duplicates the client's responsibility).

## R6. Error mapping (distinguishable, actionable)

- **Decision**: Map remote responses to the shared mapped-error hierarchy so callers can distinguish
  validation, not-found, conflict (duplicate), authentication/config, and availability/timeout
  conditions. Local validation failures raise a validation error naming the offending field before
  any network call (FR-006).
- **Rationale**: FR-009 and Principle IV require actionable, distinguishable errors; conflict handling
  is explicitly called out for duplicate-customer creation (edge case). Reusing the shared error
  hierarchy keeps error semantics uniform across resources.
- **Alternatives considered**: A single generic error type (rejected — callers can't branch on
  condition, violates FR-009); swallowing remote failures (rejected — Principle IV forbids silent
  failure).

## R7. Data protection & structured logging

- **Decision**: Reuse the shared `masking`/structured-logging concern. Customer operations log only
  non-sensitive fields (operation, customer identifier, outcome, timing). Although this feature
  handles no SAD/PAN, the masking concern still guards against accidental leakage, and customer PII
  (name/email/phone) is logged sparingly per data minimization.
- **Rationale**: Principle IV forbids SAD/PAN in logs (FR-010) and requires structured logging;
  centralizing masking makes the guarantee uniform and testable rather than per-call discipline. PII
  is not SAD but is minimized as a matter of good hygiene and the constitution's CDE-minimization
  intent.
- **Alternatives considered**: Ad-hoc per-call logging (rejected — easy to leak a field; not
  uniformly testable); logging full customer records at debug level (rejected — needless PII spread).

## R8. Testing strategy (test-first, contract-driven)

- **Decision**: RSpec, test-first. Contract tests verify (a) the public library API and (b) the BML
  remote HTTP contract via WebMock/recorded fixtures. Unit tests cover validation, error mapping, and
  pagination (empty page, page-beyond-results, next-page derivation). An opt-in, credential-gated
  sandbox integration suite proves each operation end-to-end (FR-011).
- **Rationale**: Principles II (Test-First) and III (Contract-Driven). Deterministic stubs keep the
  suite runnable without live credentials, while the gated sandbox suite provides the end-to-end proof
  the spec's success criteria require (SC-002, SC-005).
- **Alternatives considered**: Live-only integration tests (rejected — non-deterministic, needs
  secrets in CI); no contract tests (rejected — violates Principle III).

## R9. Update semantics (full replace)

- **Decision** (per the 2026-08-23 clarification): `update` uses **full-replace** semantics — the
  caller supplies the complete customer record, and any mutable field omitted from the update is
  **cleared/reset** rather than left unchanged. The platform-assigned `id` remains immutable. Local
  required-field validation (email, first name, last name) applies to update exactly as it does to
  create, since a full replace must itself be a complete, valid record.
- **Rationale**: The clarification selected full replace over partial update. Applying the same
  required-field validation to both operations keeps behavior uniform and prevents a full replace from
  silently dropping a required field. Explicit whole-record replacement avoids ambiguous merge
  semantics (Principle V: explicit over implicit).
- **Alternatives considered**: Partial update / merge (rejected — the clarification chose full
  replace; merge semantics are implicit and can mask which fields changed); mixed semantics per field
  (rejected — inconsistent and hard to test).

## Summary of resolved decisions

| Ref | Decision |
|-----|----------|
| R1 | Ruby gem; new `Customers` resource class on existing client |
| R2 | stdlib `net/http` + `json`; no new dependency |
| R3 | Platform owns the field/uniqueness contract; library additionally enforces a minimal local required set (email, first_name, last_name); phone + reference optional |
| R4 | Page-number pagination (`page` + `page_size`); default 20, max 100 (over-cap rejected); `CustomerListPage` value object; empty page (never error) for none/beyond-range |
| R5 | Reuse client env + credentials; no per-call creds; no cross-environment access |
| R6 | Shared mapped errors: validation/not-found/conflict/auth/availability, distinguishable |
| R7 | Shared masking + structured logging; no SAD/PAN; minimal PII |
| R8 | RSpec test-first; contract + unit + gated sandbox integration |
| R9 | `update` uses full-replace semantics; omitted mutable fields cleared; same required-field validation as create; `id` immutable |

All Technical Context items are resolved; no `NEEDS CLARIFICATION` remain. Ready for Phase 1.
