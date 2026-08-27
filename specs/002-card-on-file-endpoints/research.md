# Phase 0 Research: Card-on-File Endpoints

**Feature**: `002-card-on-file-endpoints` | **Date**: 2026-08-27

The specification has **no** `[NEEDS CLARIFICATION]` markers; its requirements checklist passes and
four behavioral decisions were fixed during `/speckit-clarify` (2026-08-17 and 2026-08-27 sessions):
single-use card handle as the only card input; idempotent re-store; permanent removal with a
card-data-free audit record; consent out of scope; bounded retry + configurable timeout on transient
failures; rate-limit treated as transient; store+remove audited (not reads); and "who" = client/API
identity plus optional actor reference. The remaining open items were implementation-context choices
(language, transport, testing, idempotency detection, expiry representation, list shape, error
mapping) and how to satisfy the security/observability principles. Each is resolved below.

## R1. Implementation language & packaging

- **Decision**: Ruby, packaged as a gem; the card-on-file capability is a new resource class on the
  existing client, mirroring the customer resource (`001`).
- **Rationale**: The project is named `bml_tokenization` (Ruby snake_case); the spec's Assumptions
  model the library on the sibling `bml-connect-ruby` gem "where a configured client object exposes
  per-resource classes"; features `001`/`004` already committed the library to this Ruby-gem structure.
  Any other choice would fragment the library.
- **Alternatives considered**: A separate service (rejected — the spec is a client-side integration
  library); a different language (rejected — no basis in project conventions).

## R2. HTTP transport

- **Decision**: Use Ruby standard library `net/http` + `json`; reuse the existing shared `Client` for
  base URL, environment selection, TLS, and auth headers. Add no new runtime dependency.
- **Rationale**: Constitution Principle V requires justifying every dependency; card-on-file
  request/response shapes are simple JSON over HTTPS. `bml-connect-ruby` and the sibling features use
  stdlib transport, keeping the dependency and supply-chain surface minimal.
- **Alternatives considered**: `faraday`/`httparty` (rejected — extra dependencies for no functional
  gain); a custom socket layer (rejected — reinvents TLS/HTTP unsafely).

## R3. Card input model (no raw card data)

- **Decision**: The only card input the library accepts for `store` is a **pre-tokenized, single-use
  card handle** produced by a hosted capture step (hosted fields / SDK). The library never accepts,
  transmits, stores, or logs a raw PAN or card security code (CVV/CVV2).
- **Rationale**: Spec FR-002/FR-003 and Clarification 2026-08-17; Constitution Principle I mandates
  the most protective option and forbids SAD/PAN handling. Delegating capture to a hosted step keeps
  this library out of the cardholder-data environment entirely.
- **Alternatives considered**: Accepting a PAN + expiry directly (rejected — violates Principle I and
  FR-002); accepting a multi-use token (rejected — the clarification fixed a single-use handle).

## R4. Card-on-file representation & expiry/validity status

- **Decision**: A stored card is exposed only as a **safe reference** plus a **masked summary** (card
  scheme, last four digits, expiry month/year) and an **expiry/validity status**. The masked summary
  and the exact field set are **mirrored from the platform response** rather than defined by the
  library. Validity/expiry status is surfaced as returned by the platform when present; if the
  platform returns only expiry month/year, the library exposes those and a derived `expired?`
  indicator computed from them (a read-only convenience, not new business logic). The library performs
  no payment authorization decision — using an expired card for a charge is the transactions resource's
  concern (`003`).
- **Rationale**: Spec FR-003 forbids exposing full PAN/CVV; the edge case requires expiry status to be
  discoverable. Mirroring the platform (spec Assumptions) avoids a false library-owned schema
  (Principle V). Exposing a derived `expired?` keeps the "discoverable" requirement explicit without
  duplicating platform business rules.
- **Alternatives considered**: Library-defined canonical card schema (rejected — drifts from the
  platform); omitting expiry entirely (rejected — the edge case requires it be discoverable);
  enforcing expiry at store/list time in this library (rejected — payment decisions belong to `003`).

## R5. Idempotent store — detection mechanism

- **Decision**: The remote platform is the **source of truth** for whether a card is already on file.
  On `store`, the library forwards the single-use handle and the customer association; the platform
  either creates a new card-on-file record or returns the existing one for the same underlying card.
  The library **normalizes the outcome to idempotent** — it returns the existing `CardOnFile` record
  and never creates or reports a duplicate — regardless of whether the platform signals "created" or
  "already exists" (e.g. 200 vs 201, or a conflict response carrying the existing reference). The
  library performs **no local card-fingerprint comparison** (it holds no card data to compare).
- **Rationale**: Spec FR-013 and Clarification 2026-08-17 require an idempotent outcome; spec
  Assumptions make the platform the source of truth and state the library normalizes duplicate
  handling. Because the library never sees the PAN, it cannot and must not fingerprint cards locally
  (Principle I) — it must rely on the platform's duplicate determination.
- **Alternatives considered**: Local fingerprinting/deduplication (rejected — the library has no card
  data and must not; violates Principle I); surfacing the platform's raw "duplicate" error to the
  caller (rejected — FR-013 requires normalizing to a successful idempotent return of the existing
  record); an integrator-supplied idempotency key (rejected — not required by the spec, adds surface;
  the platform already determines sameness — Principle V/YAGNI).

## R6. Transient-failure handling — timeout & bounded retry

- **Decision** (per Clarification 2026-08-27): Every operation runs within a **configurable
  per-request timeout** and, on **transient** failures (network timeout, connection drop, 5xx/
  "try again"), applies a **bounded automatic retry — at most 2 retries — with backoff** before
  failing. When retries are exhausted, the library surfaces a clear, distinguishable
  availability/timeout error. **Non-transient** errors (validation, not-found, authentication) are
  **not** retried. Retry safety is preserved because `store` is idempotent (R5) and `remove` is
  not-found-safe (removing an already-removed card yields not-found, not a second effect). This lives
  in the shared `transport` concern so every resource behaves identically.
- **Rationale**: Spec FR-014 and the outage/timeout edge case; Principle IV requires actionable
  errors and no hanging. Centralizing retry/timeout (Principle V) makes the guarantee uniform and
  testable rather than per-call discipline.
- **Alternatives considered**: No automatic retry (rejected — the clarification chose bounded retry;
  pushes avoidable checkout failures onto integrators); unbounded/aggressive retry (rejected — risks
  amplifying an outage and unbounded latency); retrying non-idempotent writes without care (rejected —
  mitigated here because store is idempotent and remove is not-found-safe).

## R7. Rate-limit handling

- **Decision** (per Clarification 2026-08-27): A rate-limit ("too many requests" / 429) response is
  treated as **transient** and retried within the same bounded budget as R6, **honoring any
  retry-after hint** the platform supplies for backoff timing. If the request is still rate-limited
  after retries, the library surfaces a **distinguishable rate-limit error** (separate from generic
  availability).
- **Rationale**: Spec FR-014 and the rate-limit edge case; honoring the server's backoff signal is
  correct client behavior and reuses the R6 retry path. A distinguishable error lets callers
  implement their own longer-term backoff if needed (FR-010, Principle IV).
- **Alternatives considered**: Surfacing rate-limit immediately without retry (rejected — the
  clarification chose transient treatment); ignoring the retry-after hint with fixed backoff
  (rejected — disrespects the server signal and risks repeated limiting); a separate unbounded
  rate-limit retry loop (rejected — unbounded latency; the clarification bounds it to the FR-014
  budget).

## R8. Environment & credential handling

- **Decision**: Every operation runs against the environment (sandbox/production) and credentials
  configured on the shared `Client`; no per-call credentials, no cross-environment access.
- **Rationale**: Spec FR-008/FR-009 and Assumptions require reusing the existing client config;
  Principle III requires sandbox/prod be selectable without code change.
- **Alternatives considered**: Per-call credential arguments (rejected — FR-009 forbids requiring
  per-call credentials; duplicates the client's responsibility).

## R9. Error mapping (distinguishable, actionable)

- **Decision**: Map remote responses to the shared mapped-error hierarchy so callers can distinguish
  **validation**, **not-found**, **conflict**, **authentication/config**, **rate-limit**, and
  **availability/timeout** conditions. Local validation failures (missing customer association or
  card handle, malformed input) raise a validation error naming the offending input before any network
  call (FR-007). The "conflict" case for a duplicate store is normalized to an idempotent success
  (R5), so a conflict error is reserved for genuinely conflicting states the platform reports that are
  not an already-on-file duplicate.
- **Rationale**: FR-010 and Principle IV require actionable, distinguishable errors; FR-014 adds a
  distinguishable rate-limit condition. Reusing the shared error hierarchy keeps error semantics
  uniform across resources.
- **Alternatives considered**: A single generic error type (rejected — callers can't branch;
  violates FR-010); swallowing remote failures (rejected — Principle IV forbids silent failure).

## R10. Auditability of state-changing operations

- **Decision** (per Clarification 2026-08-27): **`store` and `remove` each emit an audit record**;
  `list` and `retrieve` do **not**. Each audit record captures **who** (the configured client/API
  identity — e.g. the App ID — plus an **optional integrator-supplied actor reference** recorded when
  provided), **which card reference**, **when**, and **outcome**. An audit record **MUST NOT** contain
  card data beyond the safe reference (no full number, no masked summary). Emission is implemented in
  the shared `audit` concern.
- **Rationale**: Spec FR-006a/FR-015 and Constitution Principle IV require an immutable record of
  security-relevant, state-changing actions sufficient to reconstruct access without exposing
  protected data. The library only knows its own credentials, so the client identity is always
  available; the optional actor supports end-user attribution without forcing it.
- **Alternatives considered**: Auditing every operation incl. reads (rejected — the clarification
  scoped audit to state changes; reads return only masked data, adding noise/log-volume for little
  value); auditing removal only (rejected — the clarification added store); requiring a per-call actor
  (rejected — the clarification made actor optional).

## R11. List shape (no pagination)

- **Decision**: `list(customer)` returns **all** of a customer's cards on file as a `CardOnFileList`
  (a collection value object), possibly **empty**; listing a customer with no cards returns an empty
  list, **not** an error. **No pagination** is introduced, unlike the customer `list` (`001`).
- **Rationale**: A customer's set of stored cards is small and bounded (a wallet, not an unbounded
  collection), so the "page beyond results" concern that justified pagination for customers does not
  apply here (Principle V/YAGNI). Spec US2 requires enumerating a customer's cards and an empty result
  (not an error) for a customer with none; neither requires paging. If the platform later paginates
  this endpoint, pagination can be added without breaking the empty-list contract.
- **Alternatives considered**: Page-number pagination mirroring `001` (rejected — unjustified
  complexity for a small bounded set; YAGNI); returning a bare array (rejected — a named collection
  value object keeps room for platform-provided metadata and is consistent with `001`'s value-object
  approach).

## R12. Data protection & structured logging

- **Decision**: Reuse the shared `masking`/structured-logging concern. Card-on-file operations log
  only non-sensitive fields (operation, customer identifier, card safe reference, outcome, timing).
  Never log the single-use handle, PAN, CVV, or masked summary details beyond the safe reference where
  avoidable.
- **Rationale**: Principle IV/FR-003 forbid SAD/PAN in logs and require structured logging;
  centralizing masking makes the guarantee uniform and testable.
- **Alternatives considered**: Ad-hoc per-call logging (rejected — easy to leak a field; not
  uniformly testable); logging full card records (rejected — needless exposure).

## R13. Testing strategy (test-first, contract-driven)

- **Decision**: RSpec, test-first. Contract tests verify (a) the public library API and (b) the BML
  remote HTTP contract via WebMock/recorded fixtures, including **retry-then-succeed**,
  **retry-exhausted**, and **rate-limit-with-retry-after** scenarios, and **audit emission** on
  store/remove with no card data. Unit tests cover validation, idempotent re-store, permanent removal
  (not retrievable afterward), and expiry/validity exposure. An opt-in, credential-gated sandbox
  integration suite proves each operation end-to-end (FR-012).
- **Rationale**: Principles II (Test-First) and III (Contract-Driven). Deterministic stubs keep the
  suite runnable without live credentials, while the gated sandbox suite provides the end-to-end proof
  the success criteria require (SC-003, SC-005).
- **Alternatives considered**: Live-only integration tests (rejected — non-deterministic, needs
  secrets in CI); no contract tests (rejected — violates Principle III).

## Summary of resolved decisions

| Ref | Decision |
|-----|----------|
| R1 | Ruby gem; new `CardsOnFile` resource class on existing client |
| R2 | stdlib `net/http` + `json`; no new dependency |
| R3 | Only input is a pre-tokenized single-use card handle; never a raw PAN/CVV |
| R4 | Expose safe reference + masked summary (scheme, last four, expiry) + validity status; mirror platform; derived `expired?` convenience |
| R5 | Platform is source of truth for duplicates; library normalizes to idempotent return of existing card; no local fingerprinting |
| R6 | Configurable timeout + bounded auto-retry (≤2, backoff) on transient failures; non-transient not retried; shared transport concern |
| R7 | Rate-limit treated as transient within the R6 budget, honoring retry-after; distinguishable rate-limit error |
| R8 | Reuse client env + credentials; no per-call creds; no cross-environment access |
| R9 | Shared mapped errors: validation/not-found/conflict/auth/rate-limit/availability, distinguishable |
| R10 | Audit store + remove (who = client identity + optional actor, which reference, when, outcome); reads not audited; no card data in audit |
| R11 | `list` returns all of a customer's cards (empty list, not error); no pagination |
| R12 | Shared masking + structured logging; no SAD/PAN; log only safe reference and outcome |
| R13 | RSpec test-first; contract + unit + gated sandbox integration; covers retry/rate-limit/audit |

All Technical Context items are resolved; no `NEEDS CLARIFICATION` remain. Ready for Phase 1.
