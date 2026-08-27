# Implementation Plan: Card-on-File Endpoints

**Branch**: `002-card-on-file-endpoints` | **Date**: 2026-08-27 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-card-on-file-endpoints/spec.md`

## Summary

Add a `CardsOnFile` resource class to the `bml_tokenization` client library that lets an integrator
**store**, **list**, **retrieve**, and **remove** a customer's saved payment cards on the Bank of
Maldives platform — all through the existing configured client. A card is stored by supplying a
pre-tokenized, single-use card handle produced by a hosted capture step; the library never receives,
stores, or logs a raw PAN or card security code, and every stored card is represented only by a safe
reference plus a masked summary (scheme, last four, expiry). Storing a card the customer already has
on file is idempotent (returns the existing record, no duplicate). Removal permanently deletes the
record and emits an audit record; storing also emits an audit record. Reads are not audited.
Operations validate required inputs before any remote call, run against the client's selected
environment (sandbox/production) without crossing it, authenticate with the client's configured
credentials, apply a bounded automatic retry with a configurable timeout on transient failures
(including rate-limiting), and surface distinguishable, actionable errors.

Technical approach: a thin, contract-driven Ruby resource class layered on the existing client's
HTTP/auth/config plumbing, following the same per-resource pattern used for customers (`001`),
transactions (`003`), and tokenization (`004`), verified test-first by contract and unit tests plus
an opt-in sandbox suite.

The 2026-08-27 clarifications are incorporated: transient failures get a **bounded automatic retry
(≤2, with backoff) within a configurable request timeout**, and a rate-limit response is treated as
transient honoring any retry-after hint (FR-014); **store and remove are audited** (who = configured
client/API identity plus an optional integrator-supplied actor reference, which card reference, when)
while reads are not (FR-015, FR-006a). See research.md R6/R7/R10.

## Technical Context

**Language/Version**: Ruby (target 3.1+; library targets currently-supported Ruby versions), matching
the sibling customer resource (`001`).

**Primary Dependencies**: Ruby standard library `net/http` + `json` for transport (no heavyweight HTTP
gem), following the sibling `bml-connect-ruby` approach; the feature reuses the library's existing
`Client`, configuration, error types, masking, and shared transport (including the retry/timeout
concern) rather than introducing new ones.

**Storage**: N/A — this is a stateless client library. The remote BML platform is the source of truth
for stored cards; the library persists nothing locally. Audit records are emitted (structured events),
not stored by this library.

**Testing**: RSpec for unit/contract tests; WebMock (and/or recorded fixtures) to stub the BML HTTP
contract deterministically, including transient-failure/retry and rate-limit scenarios; a thin
sandbox-integration suite (opt-in, credential-gated) proving each operation end-to-end (FR-012).
Test-first is mandatory (Constitution II).

**Target Platform**: Any Ruby runtime; distributed as a gem and embedded in integrator server-side
applications (never in an end-user browser/mobile client, since credentials live on the client and
card capture happens in a separate hosted step).

**Project Type**: Single project — a Ruby library/gem (one new resource class plus supporting value
objects and error mapping; audit + retry/timeout are shared concerns).

**Performance Goals**: Library overhead is negligible relative to the network round-trip; target < 20ms
of in-process overhead per call (serialization, validation) excluding remote latency and any
retry/backoff waits. No throughput target — concurrency and rate are governed by the caller and the
remote platform.

**Constraints**: All transport over TLS; no SAD/PAN in inputs, outputs, or logs (FR-003, SC-002);
structured, masked logging; audit records carry no card data beyond the safe reference (FR-006a,
FR-015); behavior must be identical and isolated per environment (sandbox vs production); bounded
retry (≤2) within a configurable timeout (FR-014).

**Scale/Scope**: Small and bounded — 4 operations (store, list, retrieve, remove), 2 exposed entities
(Card on File, Audit Record) plus transient input value objects, and a fixed set of mapped error
conditions. Depends on the customer resource (`001`); a customer must exist before a card is stored.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Derived from `.specify/memory/constitution.md` v1.0.0. All gates map to Principles I–V and the
Security & Compliance and Workflow sections.

| # | Gate (from principle) | How this plan satisfies it | Status |
|---|-----------------------|----------------------------|--------|
| I | SAD never persisted; PAN never plaintext/logged; tokens non-reversible; secrets injected; TLS | The library accepts only a single-use card handle produced by hosted capture and never receives a raw PAN/CVV (FR-002); stored cards are exposed solely as a safe reference + masked summary (FR-003); credentials come from the existing client config (env/secrets); all calls over TLS. Zero cardholder data at rest in this library. | PASS |
| II | Test-first; success/failure/rejection paths; no coverage reduction on security paths | Phase 1 defines contracts before code; tasks order failing contract/unit tests first, covering success, validation-rejection, not-found, idempotent re-store, permanent-removal, retry/timeout, rate-limit, audit emission, and env isolation. | PASS |
| III | Every external interface documented + versioned with contract tests; sandbox/prod selectable without code change | Phase 1 produces both the public library-API contract and the BML remote HTTP contract under `contracts/`; environment is selected via existing client config (FR-008). | PASS |
| IV | Structured logs with masking, never SAD/PAN; auditable state-changing actions; actionable errors | Structured logging reuses the shared masking concern (no card data); store + remove emit audit records capturing who/what/when/outcome with no card data beyond the safe reference (FR-006a, FR-015); mapped, distinguishable errors incl. rate-limit and availability (FR-010, FR-014). | PASS |
| V | Simplest design; justify any new abstraction/dependency; explicit over implicit | No new runtime dependency (stdlib transport reused); one resource class following the established per-resource pattern; retry/timeout and audit are shared concerns reused across resources, not per-call ad-hoc logic; idempotency + removal semantics are explicit. | PASS |

**Initial Constitution Check: PASS** — no violations; Complexity Tracking not required.

**Post-Design Constitution Check (after Phase 1): PASS** — the data model exposes only a safe
reference + masked summary (no PAN/CVV/SAD anywhere), the store contract accepts only a single-use
handle, audit records carry no card data beyond the safe reference, and logging/error mapping/retry
reuse shared concerns, so the design introduces no new constitutional risk. See re-evaluation note at
the end of Phase 1 in the artifacts.

## Project Structure

### Documentation (this feature)

```text
specs/002-card-on-file-endpoints/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   ├── library-api.md   # Public Ruby API of the CardsOnFile resource
│   └── bml-remote.md    # Remote BML HTTP request/response contract
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

The gem follows the conventional single-project Ruby layout, mirroring the sibling per-resource
structure used by customers/transactions/tokenization. Only the card-on-file-specific additions are
new; the client/config/error/masking scaffolding is shared and reused. The retry/timeout and audit
concerns are shared (added at the client/transport layer so every resource benefits), specified here
because this is the first feature to require them.

```text
lib/
└── bml_tokenization/
    ├── client.rb                 # EXISTING (shared) — configured client: base URL, env, auth, HTTP
    ├── errors.rb                 # EXISTING (shared) — mapped error hierarchy (validation/not-found/…)
    ├── resource.rb               # EXISTING (shared) — base resource behavior
    ├── masking.rb                # EXISTING (shared) — log-scrubbing helpers
    ├── transport.rb              # SHARED — request execution incl. timeout + bounded retry (FR-014)
    ├── audit.rb                  # SHARED — audit-record emission for state-changing actions (FR-015)
    ├── cards_on_file.rb          # NEW — CardsOnFile resource: store / list / retrieve / remove
    ├── card_on_file.rb           # NEW — CardOnFile value object (safe reference + masked summary)
    └── card_on_file_list.rb      # NEW — a customer's cards-on-file collection (possibly empty)

spec/                             # RSpec
├── contract/
│   ├── cards_on_file_api_spec.rb    # verifies public API contract (params, returns, errors)
│   └── cards_on_file_remote_spec.rb # verifies request/response conformance vs bml-remote.md (stubbed)
├── integration/
│   └── cards_on_file_sandbox_spec.rb # opt-in, credential-gated end-to-end against sandbox
└── unit/
    ├── cards_on_file_spec.rb        # validation, idempotency, removal, retry/timeout, rate-limit, audit
    ├── card_on_file_spec.rb         # entity behavior; no SAD/PAN exposure; expiry/validity status
    └── card_on_file_list_spec.rb    # empty list (no cards) is not an error
```

**Structure Decision**: Single Ruby gem (Project Type = library). The card-on-file capability is one
new resource class (`BmlTokenization::CardsOnFile`) plus `CardOnFile` and `CardOnFileList` value
objects, layered on the existing shared `Client`/`errors`/`resource`/`masking` plumbing and two shared
concerns — `transport` (timeout + bounded retry, FR-014) and `audit` (state-change audit emission,
FR-015). This is the minimal structure that satisfies the spec and Principle V (Simplicity), keeps
every resource uniform, and places the newly-required cross-cutting behavior where all resources reuse
it rather than duplicating it.

## Complexity Tracking

> No constitutional violations — this section intentionally left empty.
