# Implementation Plan: Tokenization Endpoints

**Branch**: `004-tokenization-endpoints` | **Date**: 2026-08-17 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-tokenization-endpoints/spec.md`

## Summary

Add a `Tokenization` resource class to the `bml_tokenization` client library that lets an integrator
**tokenize** a captured card (via a single-use hosted-capture handle), **retrieve** a token's masked
details, and **revoke** a token — all through the existing configured client. Tokens are
non-reversible, masked-only, per-account/per-environment idempotent, and every operation is audited
without ever handling, logging, or persisting the raw card number or security code. Detokenization is
explicitly not implemented. Technical approach: a thin, contract-driven Ruby resource class layered
on the existing client's HTTP/auth/config plumbing, following the same per-resource pattern already
used for customers, cards-on-file, and transactions, with masking and audit as cross-cutting concerns
verified by test-first contract and unit tests against the BML sandbox.

## Technical Context

**Language/Version**: Ruby (target 3.1+; library targets currently-supported Ruby versions)

**Primary Dependencies**: Ruby standard library `net/http` + `json` for transport (no heavyweight HTTP
gem), following the sibling `bml-connect-ruby` approach; the feature reuses the library's existing
`Client`, configuration, and error types rather than introducing new ones.

**Storage**: N/A — this is a stateless client library. It persists no cardholder data and no
Sensitive Authentication Data anywhere (FR-013). The token vault and token records live on the remote
BML platform.

**Testing**: RSpec for unit/contract tests; WebMock (and/or recorded fixtures) to stub the BML HTTP
contract deterministically; a thin sandbox-integration suite (opt-in, credential-gated) proving each
operation end-to-end (FR-014). Test-first is mandatory (Constitution II).

**Target Platform**: Any Ruby runtime; distributed as a gem and embedded in integrator server-side
applications (never in an end-user browser/mobile client, since credentials live on the client).

**Project Type**: Single project — a Ruby library/gem (one new resource class plus supporting value
objects and error mapping).

**Performance Goals**: Library overhead is negligible relative to the network round-trip; target < 20ms
of in-process overhead per call (serialization, validation, masking, audit) excluding remote latency.
No throughput target — concurrency and rate are governed by the caller and the remote platform.

**Constraints**: All transport over TLS; no PAN/CVV/SAD in inputs, outputs, logs, audit records, or
memory beyond the single request; structured, masked logging; an audit record per operation; behavior
must be identical and isolated per environment (sandbox vs production) and per account.

**Scale/Scope**: Small and bounded — 3 operations (tokenize, retrieve, revoke), 1 primary entity
(Token) plus an input-only Card Handle, and a fixed set of mapped error conditions. Consumed by the
card-on-file (`002`) and transaction (`003`) resources by token reference.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Derived from `.specify/memory/constitution.md` v1.0.0. All gates map to Principles I–V and the
Security & Compliance and Workflow sections.

| # | Gate (from principle) | How this plan satisfies it | Status |
|---|-----------------------|----------------------------|--------|
| I | SAD never persisted; PAN never plaintext; tokens non-reversible & non-sequential; detokenization guarded | Library accepts only a single-use handle (FR-002); persists nothing (FR-013); returns masked-only (FR-003); no detokenize operation exists (FR-006a); tokens non-sequential/non-reversible (FR-006). Design keeps zero at-rest card data. | PASS |
| I | Secrets injected, never committed; TLS in transit | Credentials come from the existing client config (env/secrets), not this feature; all calls over TLS. No secret handling added. | PASS |
| II | Test-first; success/failure/rejection paths; no coverage reduction on security paths | Phase 1 defines contracts before code; tasks will order failing contract/unit tests first, covering success, validation-rejection, not-found, revoked-use, and env/account isolation. | PASS |
| III | Every external interface has a documented, versioned contract with contract tests; sandbox/prod selectable without code change | Phase 1 produces both the public library-API contract and the BML remote HTTP contract under `contracts/`; environment is selected via existing client config. | PASS |
| IV | Structured logs with masking, never SAD/PAN; audit record per security-relevant op; actionable errors | Masking + structured logging as cross-cutting; audit record on tokenize/retrieve/revoke (FR-012) with account + optional actor (FR-012a); mapped, distinguishable errors (FR-010). | PASS |
| V | Simplest design; justify any new abstraction/dependency; explicit over implicit | No new runtime dependency (stdlib transport reused); one resource class following the established per-resource pattern; no hidden fallbacks. | PASS |

**Initial Constitution Check: PASS** — no violations; Complexity Tracking not required.

**Post-Design Constitution Check (after Phase 1): PASS** — the data model exposes only masked fields,
the contracts define no PAN-returning operation, and the audit/masking concerns are contract-level, so
the design introduces no new constitutional risk. See re-evaluation note at end of Phase 1.

## Project Structure

### Documentation (this feature)

```text
specs/004-tokenization-endpoints/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   ├── library-api.md   # Public Ruby API of the Tokenization resource
│   └── bml-remote.md    # Remote BML HTTP request/response contract
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

The gem follows the conventional single-project Ruby layout, mirroring the sibling per-resource
structure already assumed for customers/cards/transactions. Only the tokenization-specific additions
are new; the client/config/error scaffolding is shared and reused.

```text
lib/
└── bml_tokenization/
    ├── client.rb                 # EXISTING (shared) — configured client: base URL, env, auth, HTTP
    ├── errors.rb                 # EXISTING (shared) — mapped error hierarchy (validation/not-found/…)
    ├── resource.rb               # EXISTING (shared) — base resource behavior
    ├── audit.rb                  # shared audit-record emission (account + optional actor)
    ├── masking.rb                # shared masking/log-scrubbing helpers
    ├── tokenization.rb           # NEW — Tokenization resource: tokenize / retrieve / revoke
    └── token.rb                  # NEW — Token value object (masked summary + validity status)

spec/                             # RSpec
├── contract/
│   ├── tokenization_api_spec.rb  # verifies public API contract (params, returns, errors)
│   └── bml_remote_spec.rb        # verifies request/response conformance vs bml-remote.md (stubbed)
├── integration/
│   └── tokenization_sandbox_spec.rb  # opt-in, credential-gated end-to-end against sandbox
└── unit/
    ├── tokenization_spec.rb      # validation, masking, idempotency, revoke-no-cascade
    ├── token_spec.rb             # entity/status behavior; no PAN exposure
    └── masking_spec.rb           # ensures no PAN/CVV in any rendered output/log
```

> Note: tasks.md refines this into per-operation spec files (e.g. `tokenize_contract_spec.rb`,
> `retrieve_contract_spec.rb`, `revoke_contract_spec.rb`, and `*_sandbox_spec.rb`) so tests across
> stories parallelize; the grouping above is indicative, not binding.

**Structure Decision**: Single Ruby gem (Project Type = library). The tokenization capability is one
new resource class (`BmlTokenization::Tokenization`) plus a `Token` value object, layered on the
existing shared `Client`/`errors`/`resource` plumbing. Masking and audit are shared cross-cutting
modules so the same guarantees apply uniformly across resources. This is the minimal structure that
satisfies the spec and Principle V (Simplicity).

## Complexity Tracking

> No constitutional violations — this section intentionally left empty.
