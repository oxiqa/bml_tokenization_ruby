# Implementation Plan: Customer API Endpoints

**Branch**: `001-customer-api-endpoints` | **Date**: 2026-08-23 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-customer-api-endpoints/spec.md`

## Summary

Add a `Customers` resource class to the `bml_tokenization` client library that lets an integrator
**create**, **retrieve**, **list** (paginated), and **update** customer records on the Bank of
Maldives platform — all through the existing configured client. Operations validate required inputs
before any remote call, run against the client's selected environment (sandbox/production) without
crossing it, authenticate with the client's configured credentials, and surface distinguishable,
actionable errors. No sensitive authentication data or full card numbers are ever logged or exposed
(this feature manages the customer record only; payment-instrument/token management is out of scope).
Technical approach: a thin, contract-driven Ruby resource class layered on the existing client's
HTTP/auth/config plumbing, following the same per-resource pattern used for tokenization (`004`),
cards-on-file (`002`), and transactions (`003`), verified test-first by contract and unit tests plus
an opt-in sandbox suite.

The 2026-08-23 clarifications are incorporated: the library locally requires `first_name`,
`last_name`, and `email` (phone/reference optional); `update` uses **full-replace** semantics
(omitted mutable fields are cleared); and `list` uses **page-number** pagination with `page_size`
defaulting to 20 and capped at 100 (over-cap rejected pre-remote). See research.md R3/R4/R9.

## Technical Context

**Language/Version**: Ruby (target 3.1+; library targets currently-supported Ruby versions)

**Primary Dependencies**: Ruby standard library `net/http` + `json` for transport (no heavyweight HTTP
gem), following the sibling `bml-connect-ruby` approach; the feature reuses the library's existing
`Client`, configuration, and error types rather than introducing new ones.

**Storage**: N/A — this is a stateless client library. The remote BML platform is the source of truth
for customer records; the library persists nothing locally.

**Testing**: RSpec for unit/contract tests; WebMock (and/or recorded fixtures) to stub the BML HTTP
contract deterministically; a thin sandbox-integration suite (opt-in, credential-gated) proving each
operation end-to-end (FR-011). Test-first is mandatory (Constitution II).

**Target Platform**: Any Ruby runtime; distributed as a gem and embedded in integrator server-side
applications (never in an end-user browser/mobile client, since credentials live on the client).

**Project Type**: Single project — a Ruby library/gem (one new resource class plus supporting value
objects and error mapping).

**Performance Goals**: Library overhead is negligible relative to the network round-trip; target < 20ms
of in-process overhead per call (serialization, validation) excluding remote latency. No throughput
target — concurrency and rate are governed by the caller and the remote platform.

**Constraints**: All transport over TLS; no SAD/PAN in inputs, outputs, or logs (FR-010); structured,
masked logging; behavior must be identical and isolated per environment (sandbox vs production).

**Scale/Scope**: Small and bounded — 4 operations (create, retrieve, list, update), 2 entities
(Customer, Customer List Page), and a fixed set of mapped error conditions. Consumed indirectly by
other resources that associate customers with tokens/transactions (those associations are out of
scope here).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Derived from `.specify/memory/constitution.md` v1.0.0. All gates map to Principles I–V and the
Security & Compliance and Workflow sections.

| # | Gate (from principle) | How this plan satisfies it | Status |
|---|-----------------------|----------------------------|--------|
| I | SAD never persisted; PAN never plaintext/logged; secrets injected; TLS in transit | This feature handles only customer contact records — it never receives, stores, or logs PAN/CVV/SAD (FR-010); credentials come from the existing client config (env/secrets), not this feature; all calls over TLS. Zero cardholder data at rest. | PASS |
| II | Test-first; success/failure/rejection paths; no coverage reduction on security paths | Phase 1 defines contracts before code; tasks will order failing contract/unit tests first, covering success, validation-rejection, not-found, conflict, pagination bounds, and env isolation. | PASS |
| III | Every external interface has a documented, versioned contract with contract tests; sandbox/prod selectable without code change | Phase 1 produces both the public library-API contract and the BML remote HTTP contract under `contracts/`; environment is selected via existing client config (FR-007). | PASS |
| IV | Structured logs with masking, never SAD/PAN; actionable, distinguishable errors | Structured logging reuses the shared masking concern; mapped, distinguishable errors for validation/not-found/conflict/auth/availability (FR-009). Customer PII (name/email/phone) is handled per data-minimization but is not SAD. | PASS |
| V | Simplest design; justify any new abstraction/dependency; explicit over implicit | No new runtime dependency (stdlib transport reused); one resource class following the established per-resource pattern; no hidden fallbacks. | PASS |

**Initial Constitution Check: PASS** — no violations; Complexity Tracking not required.

**Post-Design Constitution Check (after Phase 1): PASS** — the data model exposes only customer
contact fields (no SAD/PAN anywhere), the contracts define no card-data-bearing operation, and
logging/error mapping reuse the shared masking concern, so the design introduces no new
constitutional risk. See re-evaluation note at end of Phase 1.

## Project Structure

### Documentation (this feature)

```text
specs/001-customer-api-endpoints/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   ├── library-api.md   # Public Ruby API of the Customers resource
│   └── bml-remote.md    # Remote BML HTTP request/response contract
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

The gem follows the conventional single-project Ruby layout, mirroring the sibling per-resource
structure used by tokenization/cards/transactions. Only the customer-specific additions are new; the
client/config/error scaffolding is shared and reused.

```text
lib/
└── bml_tokenization/
    ├── client.rb                 # EXISTING (shared) — configured client: base URL, env, auth, HTTP
    ├── errors.rb                 # EXISTING (shared) — mapped error hierarchy (validation/not-found/…)
    ├── resource.rb               # EXISTING (shared) — base resource behavior
    ├── masking.rb                # EXISTING (shared) — log-scrubbing helpers
    ├── customers.rb              # NEW — Customers resource: create / retrieve / list / update
    ├── customer.rb               # NEW — Customer value object (record returned to caller)
    └── customer_list_page.rb     # NEW — paginated list page (records + page/page_size + has_next)

spec/                             # RSpec
├── contract/
│   ├── customers_api_spec.rb     # verifies public API contract (params, returns, errors)
│   └── customers_remote_spec.rb  # verifies request/response conformance vs bml-remote.md (stubbed)
├── integration/
│   └── customers_sandbox_spec.rb # opt-in, credential-gated end-to-end against sandbox
└── unit/
    ├── customers_spec.rb         # validation, error mapping, pagination behavior
    ├── customer_spec.rb          # entity behavior; no SAD/PAN exposure
    └── customer_list_page_spec.rb # empty page, page-beyond-results, next-page derivation
```

**Structure Decision**: Single Ruby gem (Project Type = library). The customer capability is one new
resource class (`BmlTokenization::Customers`) plus `Customer` and `CustomerListPage` value objects,
layered on the existing shared `Client`/`errors`/`resource`/`masking` plumbing. This is the minimal
structure that satisfies the spec and Principle V (Simplicity), and it keeps every resource uniform.

## Complexity Tracking

> No constitutional violations — this section intentionally left empty.
