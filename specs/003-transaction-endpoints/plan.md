# Implementation Plan: Transaction Endpoints

**Branch**: `003-transaction-endpoints` | **Date**: 2026-08-27 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-transaction-endpoints/spec.md`

## Summary

Add a `Transactions` resource class to the `bml_tokenization` client library that lets an integrator
**create**, **retrieve**, and **list** payments on the Bank of Maldives platform — all through the
existing configured client. Create supports two completion paths: (a) with **no stored card**, it
returns a **hosted payment URL** (status `pending`) that the customer completes in the browser, using
an integrator-supplied return/redirect URL that is **required** for this path; (b) with a
**card-on-file safe reference**, the payment is **charged server-side** with no redirect and the
returned record reflects the resulting status directly. Every transaction references an **existing
customer** (no guest payments), the amount is a **positive integer in MVR minor units**, and the
currency is **MVR only** (validated locally). Create is **idempotent on a global integrator
reference**: an identical repeat returns the existing transaction with no second charge, while a
reused reference carrying different material parameters returns a **conflict** error. Status is one of
four distinct values — `pending`, `succeeded`, `failed`, `cancelled`. List is **page-number
paginated** (default 20, max 100) with optional, combinable **customer** and **status** filters.
Create and retrieve emit an **audit record** (who/what/when/outcome) with no card data; the library
never accepts, returns, logs, or persists a full PAN or CVV — a saved card is referenced only by its
safe reference.

Technical approach: a thin, contract-driven Ruby resource class layered on the existing client's
HTTP/auth/config plumbing, following the same per-resource pattern used for customers (`001`),
cards on file (`002`), and tokenization (`004`), and reusing the shared `transport` (timeout +
bounded retry) and `audit` concerns. Verified test-first by contract and unit tests plus an opt-in,
credential-gated sandbox suite.

The 2026-08-27 clarifications are incorporated: **MVR-only** currency validation (FR-005c); **four
distinct statuses** (FR-006); **page-number pagination** matching the customer resource (default 20,
max 100 — FR-004); **idempotency-conflict** on a reused reference with differing parameters and a
**global** reference namespace (FR-013); and a **return URL required for the redirect flow only**
(FR-002). See research.md R6–R10.

## Technical Context

**Language/Version**: Ruby (target 3.1+; library targets currently-supported Ruby versions), matching
the sibling customer (`001`) and card-on-file (`002`) resources.

**Primary Dependencies**: Ruby standard library `net/http` + `json` for transport (no heavyweight HTTP
gem), following the sibling `bml-connect-ruby` approach; the feature reuses the library's existing
`Client`, configuration, error types, masking, and shared `transport`/`audit` concerns rather than
introducing new ones.

**Storage**: N/A — this is a stateless client library. The remote BML platform is the source of truth
for transaction records; the library persists nothing locally. Audit records are emitted (structured
events), not stored by this library.

**Testing**: RSpec for unit/contract tests; WebMock (and/or recorded fixtures) to stub the BML HTTP
contract deterministically, including the redirect vs stored-card paths, idempotent replay, idempotency
conflict, pagination bounds, and status-filter validation; a thin sandbox-integration suite (opt-in,
credential-gated) proving each operation end-to-end (FR-011). Test-first is mandatory (Constitution II).

**Target Platform**: Any Ruby runtime; distributed as a gem and embedded in integrator **server-side**
applications (credentials live on the client, and new-card capture happens in a separate hosted step —
never in an end-user browser/mobile client).

**Project Type**: Single project — a Ruby library/gem (one new resource class plus supporting value
objects and error mapping; `transport` and `audit` are shared concerns reused from `002`).

**Performance Goals**: Library overhead is negligible relative to the network round-trip; target
< 20ms of in-process overhead per call (serialization, validation) excluding remote latency and any
retry/backoff waits. No throughput target — concurrency and rate are governed by the caller and the
remote platform.

**Constraints**: All transport over TLS; no PAN/CVV/SAD in inputs, outputs, or logs (FR-010, SC-005);
structured, masked logging; audit records carry no card data beyond the safe reference (FR-012);
behavior must be identical and isolated per environment (sandbox vs production — FR-007); amount is a
positive integer in MVR minor units (FR-005b) and currency is MVR only (FR-005c).

**Scale/Scope**: Small and bounded — 3 operations (create, retrieve, list), 2 exposed entities
(Transaction, Transaction List Page) plus transient input value objects, and a fixed set of mapped
error conditions (validation, not-found, **conflict**, auth, availability). Depends on the customer
resource (`001`); optionally references the card-on-file resource (`002`) for the stored-card path.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Derived from `.specify/memory/constitution.md` v1.0.0. All gates map to Principles I–V and the
Security & Compliance and Workflow sections.

| # | Gate (from principle) | How this plan satisfies it | Status |
|---|-----------------------|----------------------------|--------|
| I | SAD never persisted; PAN never plaintext/logged; tokens non-reversible; secrets injected; TLS | The library never accepts, returns, logs, or persists a full PAN or CVV (FR-010); a saved card is referenced **only** by the card-on-file safe reference; new-card capture is delegated to the platform's hosted flow (payment URL); credentials come from the existing client config (env/secrets); all calls over TLS. Zero cardholder data at rest in this library. | PASS |
| II | Test-first; success/failure/rejection paths; no coverage reduction on security paths | Phase 1 defines contracts before code; tasks order failing contract/unit tests first, covering both create paths, validation-rejection (amount, currency, missing customer, missing return URL), not-found, idempotent replay, **idempotency conflict**, pagination bounds, status-filter validation, and env isolation. | PASS |
| III | Every external interface documented + versioned with contract tests; sandbox/prod selectable without code change | Phase 1 produces both the public library-API contract and the BML remote HTTP contract under `contracts/`; environment is selected via existing client config (FR-007, FR-008). | PASS |
| IV | Structured logs with masking, never SAD/PAN; auditable state-changing actions; actionable errors | Structured logging reuses the shared masking concern (no card data, no payment URL secrets); **create and retrieve** emit audit records capturing who/what/when/outcome with no card data (FR-012); mapped, distinguishable errors incl. conflict, auth, and availability (FR-009). | PASS |
| V | Simplest design; justify any new abstraction/dependency; explicit over implicit | No new runtime dependency (stdlib transport reused); one resource class following the established per-resource pattern; `transport` (timeout + bounded retry) and `audit` are shared concerns reused from `002`; idempotency, conflict, and the two create paths are explicit, not implicit fallbacks. | PASS |

**Initial Constitution Check: PASS** — no violations; Complexity Tracking not required.

**Post-Design Constitution Check (after Phase 1): PASS** — the data model exposes no PAN/CVV/SAD
anywhere (a stored card appears only as its safe reference; the new-card path exposes only a hosted
payment URL), create/retrieve audit records carry no card data, and logging/error-mapping/retry reuse
shared concerns, so the design introduces no new constitutional risk. Bounded automatic retry is safe
for create because the **global integrator reference is the idempotency key** — a retried create
cannot double-charge (research R2/R8). See the re-evaluation note at the end of Phase 1 in the
artifacts.

## Project Structure

### Documentation (this feature)

```text
specs/003-transaction-endpoints/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   ├── library-api.md   # Public Ruby API of the Transactions resource
│   └── bml-remote.md    # Remote BML HTTP request/response contract
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

The gem follows the conventional single-project Ruby layout, mirroring the sibling per-resource
structure used by customers/cards-on-file/tokenization. Only the transaction-specific additions are
new; the client/config/error/masking/transport/audit scaffolding is shared and reused.

```text
lib/
└── bml_tokenization/
    ├── client.rb                 # EXISTING (shared) — configured client: base URL, env, auth, HTTP
    ├── errors.rb                 # EXISTING (shared) — mapped error hierarchy (validation/not-found/…)
    ├── resource.rb               # EXISTING (shared) — base resource behavior
    ├── masking.rb                # EXISTING (shared) — log-scrubbing helpers
    ├── transport.rb              # SHARED (from 002) — request execution incl. timeout + bounded retry
    ├── audit.rb                  # SHARED (from 002) — audit-record emission
    ├── transactions.rb           # NEW — Transactions resource: create / retrieve / list
    ├── transaction.rb            # NEW — Transaction value object (status, amount, payment URL, refs)
    └── transaction_list.rb       # NEW — Transaction List Page (records + pagination metadata)

spec/                             # RSpec
├── contract/
│   ├── transactions_api_spec.rb     # verifies public API contract (params, returns, errors)
│   └── transactions_remote_spec.rb  # verifies request/response conformance vs bml-remote.md (stubbed)
├── integration/
│   └── transactions_sandbox_spec.rb # opt-in, credential-gated end-to-end against sandbox
└── unit/
    ├── transactions_spec.rb         # both create paths, validation, idempotency+conflict, list filters
    ├── transaction_spec.rb          # entity behavior; four statuses; no PAN/CVV exposure
    └── transaction_list_spec.rb     # pagination (default 20 / max 100), empty page is not an error
```

**Structure Decision**: Single Ruby gem (Project Type = library). The transaction capability is one
new resource class (`BmlTokenization::Transactions`) plus `Transaction` and `TransactionList` value
objects, layered on the existing shared `Client`/`errors`/`resource`/`masking` plumbing and the
`transport` (timeout + bounded retry) and `audit` concerns already introduced by `002`. This is the
minimal structure that satisfies the spec and Principle V (Simplicity), keeps every resource uniform,
and reuses cross-cutting behavior rather than duplicating it.

## Complexity Tracking

> No constitutional violations — this section intentionally left empty.
