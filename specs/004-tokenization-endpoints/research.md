# Phase 0 Research: Tokenization Endpoints

**Feature**: `004-tokenization-endpoints` | **Date**: 2026-08-17

The specification was fully clarified (5/5 clarifications resolved; no `[NEEDS CLARIFICATION]`
markers). No spec-level unknowns remained for research. The open items were implementation-context
choices (language, transport, testing, and how to satisfy the security/audit principles). Each is
resolved below.

## R1. Implementation language & packaging

- **Decision**: Ruby, packaged as a gem; the tokenization capability is a new resource class on the
  existing client.
- **Rationale**: The project is named `bml_tokenization` (Ruby snake_case), the feature request was
  "add a class", and the spec's own Assumptions across features `001`–`004` model the library on the
  sibling **`bml-connect-ruby`** gem, "where a configured client object exposes per-resource classes."
  No source exists yet, but every convention points to Ruby. Choosing anything else would contradict
  the stated project structure.
- **Alternatives considered**: A separate service/microservice (rejected — the spec is explicitly a
  client-side integration library, not a service); a different language (rejected — no basis in the
  project conventions and would fragment the library).

## R2. HTTP transport

- **Decision**: Use Ruby standard library `net/http` + `json`; reuse the existing shared `Client` for
  base URL, environment selection, TLS, and authentication headers. Add no new runtime dependency.
- **Rationale**: Constitution Principle V (Simplicity) requires justifying every dependency; the
  request/response shapes here are simple JSON over HTTPS. `bml-connect-ruby` uses stdlib transport,
  keeping the dependency and supply-chain surface minimal (Security & Compliance: "known-vulnerable
  dependencies MUST be remediated"). Fewer deps = smaller attack surface.
- **Alternatives considered**: `faraday`/`httparty` (rejected — extra dependencies and indirection for
  no functional gain); a custom socket layer (rejected — reinvents TLS/HTTP unsafely).

## R3. Card input model (handle vs raw PAN)

- **Decision**: Accept only a single-use hosted-capture card handle; never accept raw PAN/CVV.
- **Rationale**: Clarification Q4 confirmed this, and Constitution Principle I mandates minimizing the
  cardholder-data environment. The library therefore stays out of full PCI scope; raw card data is
  captured by a hosted step (hosted fields / SDK) that the integrator wires up separately.
- **Alternatives considered**: Accepting raw PAN over TLS (rejected — pulls the library into full PCI
  scope and contradicts the constitution and clarification).

## R4. Token non-reversibility, non-sequentiality, and scope

- **Decision**: The remote BML platform issues the token value; the library treats it as an opaque,
  non-reversible reference and never derives, decrypts, or reverses it. Idempotency ("same card → same
  token") is scoped per merchant/app account and per environment (Clarification Q2).
- **Rationale**: Principle I requires tokens be non-sequential and non-reversible without vault access,
  which the library does not have. Per-account/per-environment scope prevents cross-merchant
  correlation of cardholders and preserves environment isolation (FR-008, FR-011).
- **Alternatives considered**: Library-side token generation (rejected — the library has no vault and
  must not hold card data); global one-token-per-card (rejected in Q2 for privacy/correlation risk).

## R5. Detokenization

- **Decision**: Not implemented. No operation returns, reconstructs, or reveals a full card number.
- **Rationale**: Clarification Q1 + FR-006a. The constitution treats detokenization as a specially
  authorized, audited system capability outside this integration library's remit. Omitting it keeps
  the surface write-only-plus-masked-read, which is far easier to secure and certify.
- **Alternatives considered**: An authorized+audited detokenize path (rejected in Q1; would materially
  enlarge the CDE and compliance burden).

## R6. Revocation semantics (no cascade)

- **Decision**: Revoke permanently invalidates the token; the library does not delete or mutate
  card-on-file records or transactions that reference it. Any later use of a revoked token is rejected
  at use time by the consuming operation.
- **Rationale**: Clarification Q3 + FR-005a. Keeps resources decoupled and avoids surprising
  cross-resource side effects; use-time rejection is sufficient to guarantee "no longer usable."
- **Alternatives considered**: Cascade delete (rejected — cross-resource coupling/side effects);
  block-if-referenced (rejected — adds a precondition and error path without security benefit).

## R7. Masking & structured logging

- **Decision**: A shared `masking` module scrubs/masks every rendered value; the library logs
  structured events that contain only the token reference, masked summary, operation, outcome, and
  timing — never PAN/CVV/SAD. Value objects' inspect/to_s are overridden to prevent accidental leakage.
- **Rationale**: Principle IV requires structured, masked logging and forbids SAD/PAN in logs. Making
  masking a shared concern (not per-call discipline) makes the guarantee testable and uniform.
- **Alternatives considered**: Ad-hoc per-call masking (rejected — easy to miss a path; not uniformly
  testable).

## R8. Auditability (who/what/when/outcome)

- **Decision**: A shared `audit` module emits one record per tokenize/retrieve/revoke capturing the
  account identity ("who" default), an optional integrator-supplied actor reference, the affected
  token reference, timestamp, operation, and outcome — with no card data. Actor is optional, never
  required (FR-012a).
- **Rationale**: Principle IV requires an audit record for every security-relevant action sufficient to
  reconstruct access without exposing protected data. Account-default + optional actor (Q5) balances
  low caller burden with richer attribution.
- **Alternatives considered**: Mandatory per-call actor (rejected in Q5 — burden); account-only
  (rejected in Q5 — weaker attribution).

## R9. Testing strategy (test-first, contract-driven)

- **Decision**: RSpec, test-first. Contract tests verify (a) the public library API and (b) the BML
  remote HTTP contract via WebMock/recorded fixtures. Unit tests cover validation, masking,
  idempotency, and revoke-no-cascade. An opt-in, credential-gated sandbox integration suite proves each
  operation end-to-end (FR-014). A dedicated masking test asserts no PAN/CVV appears in any output/log.
- **Rationale**: Principles II (Test-First) and III (Contract-Driven). Deterministic stubs keep the
  suite runnable without live credentials, while the gated sandbox suite provides the end-to-end proof
  the spec's success criteria require.
- **Alternatives considered**: Live-only integration tests (rejected — non-deterministic, needs
  secrets in CI); no contract tests (rejected — violates Principle III).

## Summary of resolved decisions

| Ref | Decision |
|-----|----------|
| R1 | Ruby gem; new resource class on existing client |
| R2 | stdlib `net/http` + `json`; no new dependency |
| R3 | Single-use hosted-capture handle only; no raw PAN |
| R4 | Opaque, non-reversible token; idempotent per account + environment |
| R5 | No detokenization |
| R6 | Revoke = permanent invalidation, no cascade, reject-on-use |
| R7 | Shared masking + structured logging; safe inspect/to_s |
| R8 | Shared audit: account default + optional actor, no card data |
| R9 | RSpec test-first; contract + unit + gated sandbox integration |

All Technical Context items are resolved; no `NEEDS CLARIFICATION` remain. Ready for Phase 1.
