<!--
Sync Impact Report
==================
Version change: (none) → 1.0.0
Rationale: Initial ratification of the project constitution (MAJOR baseline).

Modified principles: (none — initial adoption)
Added principles:
  - I. Security & Cardholder Data Protection (NON-NEGOTIABLE)
  - II. Test-First (NON-NEGOTIABLE)
  - III. Contract-Driven Integration
  - IV. Observability & Auditability
  - V. Simplicity & Explicitness
Added sections:
  - Security & Compliance Requirements
  - Development Workflow & Quality Gates
  - Governance

Removed sections: (none)

Templates & artifacts requiring review:
  - .specify/templates/plan-template.md — ensure Constitution Check gates map to Principles I–V
  - .specify/templates/spec-template.md — confirm security/compliance requirements are captured
  - .specify/templates/tasks-template.md — confirm test-first task ordering is enforced

Deferred items / follow-up TODOs: (none)
-->

# BML Tokenization Constitution

## Core Principles

### I. Security & Cardholder Data Protection (NON-NEGOTIABLE)

Protecting cardholder data is the primary reason this service exists; every design and code
decision MUST default to the most protective option.

- Sensitive Authentication Data (full track data, CVV/CVV2, PIN/PIN blocks) MUST NEVER be
  persisted after authorization, in any store, log, cache, or backup.
- The Primary Account Number (PAN) MUST NOT be stored in plaintext. When a PAN must be retained
  it MUST be replaced by a token; any at-rest representation MUST be encrypted with a
  managed, rotatable key.
- Tokens MUST NOT be reversible without access to the protected token vault; token values MUST
  be non-sequential and MUST carry no exploitable relationship to the PAN.
- Detokenization MUST require explicit, authenticated, and authorized access and MUST be
  recorded in the audit trail (see Principle IV).
- Secrets (API keys, App IDs, encryption keys, DB credentials) MUST be injected from the
  environment or a secrets manager and MUST NEVER be committed to source control.
- All data in transit MUST use TLS; internal service-to-service traffic MUST be authenticated.

Rationale: This service handles Bank of Maldives payment credentials. A single leak of PAN or
authentication data is a regulatory and reputational failure that no other quality can offset.

### II. Test-First (NON-NEGOTIABLE)

Tests define behavior before implementation exists.

- Every change to production behavior MUST begin with a failing test that expresses the intended
  behavior; implementation follows to make it pass (Red-Green-Refactor).
- Tokenization, detokenization, and cryptographic boundaries MUST have tests covering success,
  failure, and rejection paths, including malformed and out-of-range inputs.
- A change MUST NOT be merged if it reduces coverage of security-critical paths.

Rationale: Payment logic is unforgiving; test-first prevents regressions in exactly the code
paths where silent failure is most costly.

### III. Contract-Driven Integration

Boundaries with external systems (notably the BML Connect API) are defined by explicit,
versioned contracts.

- Every external interface (HTTP API, message schema, BML Connect request/response) MUST have a
  documented contract, and contract tests MUST verify conformance.
- Backward-incompatible contract changes MUST be versioned and MUST NOT break existing consumers
  without an explicit migration path.
- Sandbox and production configurations MUST be selectable without code changes.

Rationale: A tokenization service is only useful when its callers and the payment gateway can
rely on stable, verifiable interfaces.

### IV. Observability & Auditability

The system MUST be diagnosable in production and MUST retain an immutable record of
security-relevant actions.

- Logging MUST be structured (machine-parseable) and MUST NEVER contain PAN, CVV, PIN, full
  track data, or secrets; sensitive fields MUST be masked or omitted.
- Every tokenize, detokenize, and key-access operation MUST produce an audit record capturing
  who, what, when, and outcome — sufficient to reconstruct access without exposing the protected
  data itself.
- Errors MUST be surfaced with actionable context; silent failure of a security control is a
  defect.

Rationale: Debuggability and audit are inseparable here — the same events operators need to
troubleshoot are the events compliance requires us to prove.

### V. Simplicity & Explicitness

Prefer the simplest design that satisfies the requirement and the security principles above.

- Apply YAGNI: build for current, specified requirements, not speculative ones.
- Additional abstraction, indirection, or dependency MUST be justified by a concrete need;
  unjustified complexity MUST be removed in review.
- Behavior MUST be explicit over implicit — no hidden fallbacks that weaken a security control.

Rationale: Complexity is where security bugs hide; a smaller, clearer surface is easier to
review, test, and defend.

## Security & Compliance Requirements

- The service operates on Bank of Maldives payment credentials and MUST be designed to align
  with PCI DSS expectations for handling, storing, and transmitting cardholder data.
- Encryption keys MUST be rotatable, and key material MUST be isolated from the encrypted data
  it protects.
- The cardholder-data environment MUST be minimized: components that do not require access to
  PAN or the token vault MUST NOT have it.
- Dependencies MUST be tracked, and known-vulnerable dependencies MUST be remediated before
  release.
- BML Connect credentials (API key, App ID) and their mode (`production` / `sandbox`) MUST be
  configuration-driven and MUST NOT be hardcoded.

## Development Workflow & Quality Gates

- Every pull request MUST pass automated tests and MUST demonstrate compliance with Principles
  I–V; reviewers MUST explicitly verify the security and test-first principles.
- Changes touching cryptographic, tokenization, or data-persistence code MUST receive review
  from at least one reviewer other than the author.
- Secrets scanning MUST run against changes; a detected secret blocks merge until remediated.
- A change that cannot be verified by an automated or documented test MUST NOT be merged until
  such verification exists or the gap is explicitly justified and recorded.

## Governance

This constitution supersedes other development practices for this project. Where a practice
conflicts with a principle here, the principle wins.

- Amendments MUST be proposed as a change to this document, MUST state the rationale, and MUST
  update the version and dates below.
- Versioning follows semantic versioning: MAJOR for backward-incompatible governance or
  principle removals/redefinitions, MINOR for a newly added or materially expanded principle or
  section, PATCH for clarifications and non-semantic refinements.
- All PRs and reviews MUST verify compliance with this constitution; unjustified complexity or
  weakened security controls MUST be rejected.
- Runtime development guidance for agents and contributors is maintained alongside the Spec Kit
  templates in `.specify/`; those templates MUST stay consistent with the principles above.

**Version**: 1.0.0 | **Ratified**: 2026-08-17 | **Last Amended**: 2026-08-17
