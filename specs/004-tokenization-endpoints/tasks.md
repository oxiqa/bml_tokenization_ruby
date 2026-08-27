---
description: "Task list for Tokenization Endpoints implementation"
---

# Tasks: Tokenization Endpoints

**Input**: Design documents from `/specs/004-tokenization-endpoints/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: INCLUDED — Constitution Principle II (Test-First) is NON-NEGOTIABLE, and plan.md/research.md
(R9) mandate RSpec contract + unit + credential-gated sandbox tests. Every story writes tests first;
they MUST fail before implementation.

**Organization**: Tasks are grouped by user story (from spec.md) for independent implementation and
testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1 / US2 / US3 (user-story tasks only)
- Paths follow the Ruby-gem layout in plan.md (`lib/bml_tokenization/`, `spec/`)

## Path Conventions

Single-project Ruby gem: source in `lib/bml_tokenization/`, specs in `spec/` at repository root.

**Shared-file note**: the three operations live in one resource file
`lib/bml_tokenization/tokenization.rb`. Its skeleton is created in Foundational (T012); each story then
**adds its own method** to that file, so implementation edits to `tokenization.rb` across stories are
sequential (not `[P]`). All spec files are per-operation, so tests across stories ARE parallelizable.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Initialize the gem project and test tooling.

- [ ] T001 Create gem project structure: entrypoint `lib/bml_tokenization.rb`, `lib/bml_tokenization/` package dir, `spec/` tree (`spec/contract/`, `spec/unit/`, `spec/integration/`), and `bml_tokenization.gemspec` + `Gemfile`
- [ ] T002 Add development dependencies (rspec, webmock, rubocop, bundler-audit) to the gemspec/Gemfile and create `spec/spec_helper.rb` + `.rspec` (require WebMock, disable real HTTP by default)
- [ ] T003 [P] Configure linting/formatting and secret-scanning config: `.rubocop.yml` and a committed secrets-scan config (Constitution: secrets scanning MUST run)

**Checkpoint**: `bundle exec rspec` runs (zero specs) and `bundle exec rubocop` runs clean on the skeleton.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared client/transport/error/masking/audit plumbing and core value objects that ALL
stories depend on. Per plan.md these are shared across resources.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Foundational tests (write first, MUST fail) ⚠️

- [ ] T004 [P] Unit test: masking scrubs PAN/CVV/handle and value objects have safe `inspect`/`to_s`, in `spec/unit/masking_spec.rb`
- [ ] T005 [P] Unit test: `Token` exposes only masked fields (`reference`, `scheme`, `last4`, `expiry_month`, `expiry_year`, `status`) and never a full PAN via `inspect`/`to_s`/`to_h`, in `spec/unit/token_spec.rb`

### Foundational implementation

- [ ] T006 Create configured `Client` (base URL, environment selection sandbox/production, TLS enforcement, injected credentials/auth headers) in `lib/bml_tokenization/client.rb` (FR-008, FR-009)
- [ ] T007 [P] Create mapped error hierarchy (validation, not-found, already-revoked, conflict, authentication/config, availability/timeout) in `lib/bml_tokenization/errors.rb` (FR-010)
- [ ] T008 [P] Create `Masking` module (scrub/mask rendered values; helper for structured, PAN/CVV-free logging) in `lib/bml_tokenization/masking.rb` (FR-003, FR-013, R7)
- [ ] T009 [P] Create `Audit` module (emit one record with account default + optional actor, token ref, timestamp, operation, outcome; never card data) in `lib/bml_tokenization/audit.rb` (FR-012, FR-012a, R8)
- [ ] T010 Create base `Resource` (JSON transport over `net/http`, environment routing, response→error mapping) in `lib/bml_tokenization/resource.rb` (depends on T006, T007) (R2)
- [ ] T011 [P] Create `Token` value object (masked fields + `status` enum `active`/`revoked`/`expired`, safe `inspect`/`to_s`/`to_h`) in `lib/bml_tokenization/token.rb` (depends on T008) (data-model Token)
- [ ] T012 Create `Tokenization` resource skeleton (empty class inheriting base `Resource`) and wire the `client.tokenization` accessor, in `lib/bml_tokenization/tokenization.rb` and `lib/bml_tokenization/client.rb` (depends on T010) (FR-001)

**Checkpoint**: Foundation ready — masking/token tests pass; `client.tokenization` returns the resource; user stories can now begin.

---

## Phase 3: User Story 1 - Tokenize a captured card (Priority: P1) 🎯 MVP

**Goal**: Convert a single-use hosted-capture card handle into a masked, non-reversible token via
`client.tokenization.tokenize(handle)`.

**Independent Test**: Tokenize a valid sandbox handle → receive a `Token` (`active`) with masked
summary and no full PAN/CVV; invalid handle → error, no token; same card twice → same token.

### Tests for User Story 1 (write first, MUST fail) ⚠️

- [ ] T013 [P] [US1] Contract test for `tokenize` — public API shape + BML create-token remote stub (WebMock), asserting masked-only output and auth header present / no PAN in request or log — in `spec/contract/tokenize_contract_spec.rb` (contracts/library-api.md, contracts/bml-remote.md)
- [ ] T014 [P] [US1] Unit test for `tokenize` validation (blank handle rejected pre-remote; PAN-looking `actor` rejected) and idempotency (same card + account + env → existing token) in `spec/unit/tokenize_spec.rb` (FR-007, FR-011)
- [ ] T015 [P] [US1] Integration test (sandbox, credential-gated; skips without creds) for tokenize end-to-end in `spec/integration/tokenize_sandbox_spec.rb` (FR-014)

### Implementation for User Story 1

- [ ] T016 [US1] Implement `Tokenization#tokenize(card_handle, actor: nil)` → builds and returns `Token`, in `lib/bml_tokenization/tokenization.rb` (depends on T012, T011)
- [ ] T017 [US1] Add local input validation to `tokenize` (reject blank/missing handle and PAN-looking actor before any remote call), in `lib/bml_tokenization/tokenization.rb` (FR-007)
- [ ] T018 [US1] Add idempotency normalization to `tokenize` (same underlying card within account + environment returns the existing token; never a duplicate), in `lib/bml_tokenization/tokenization.rb` (FR-011)
- [ ] T019 [US1] Emit `tokenize` audit record + masked structured log (account + optional actor, resulting token reference, outcome; no card data), in `lib/bml_tokenization/tokenization.rb` (FR-012, FR-012a)

**Checkpoint**: US1 fully functional and independently testable — tokenize works end-to-end (MVP).

---

## Phase 4: User Story 2 - Retrieve token details (Priority: P1)

**Goal**: Look up a token's current masked details and validity status via
`client.tokenization.retrieve(reference)`.

**Independent Test**: Retrieve an issued token → masked summary + `status`, no full PAN; unknown
reference → not-found error.

### Tests for User Story 2 (write first, MUST fail) ⚠️

- [ ] T020 [P] [US2] Contract test for `retrieve` — public API + BML get-token remote stub, asserting masked-only output and `status` present — in `spec/contract/retrieve_contract_spec.rb` (contracts/*)
- [ ] T021 [P] [US2] Unit test for `retrieve` (unknown reference → not-found; returned `Token` exposes no full PAN via any accessor/inspect) in `spec/unit/retrieve_spec.rb` (FR-004, US2-2)
- [ ] T022 [P] [US2] Integration test (sandbox, credential-gated) for retrieve in `spec/integration/retrieve_sandbox_spec.rb` (FR-014)

### Implementation for User Story 2

- [ ] T023 [US2] Implement `Tokenization#retrieve(reference, actor: nil)` → returns `Token` (masked summary + status), in `lib/bml_tokenization/tokenization.rb` (depends on T012, T011) — shares file with US1/US3, sequence edits
- [ ] T024 [US2] Map unknown-reference response to the not-found error for `retrieve`, in `lib/bml_tokenization/tokenization.rb` (FR-010)
- [ ] T025 [US2] Emit `retrieve` audit record (account + optional actor, token reference, outcome), in `lib/bml_tokenization/tokenization.rb` (FR-012)

**Checkpoint**: US1 and US2 both work independently.

---

## Phase 5: User Story 3 - Revoke a token (Priority: P2)

**Goal**: Permanently invalidate a token via `client.tokenization.revoke(reference)` with no cascade to
referencing resources.

**Independent Test**: Revoke a token → `revoked` (terminal); later use rejected; a referenced
card-on-file record is NOT deleted/altered; revoking unknown/already-revoked → not-found/already-revoked.

### Tests for User Story 3 (write first, MUST fail) ⚠️

- [ ] T026 [P] [US3] Contract test for `revoke` — public API + BML revoke remote stub, asserting the library issues NO additional calls to mutate other resources (no-cascade) — in `spec/contract/revoke_contract_spec.rb` (contracts/*, FR-005a)
- [ ] T027 [P] [US3] Unit test for `revoke` (permanence/no reactivation; already-revoked → error; use-after-revoke rejected; no-cascade: referencing record untouched) in `spec/unit/revoke_spec.rb` (FR-005, FR-005a, US3-2, US3-3)
- [ ] T028 [P] [US3] Integration test (sandbox, credential-gated) for revoke in `spec/integration/revoke_sandbox_spec.rb` (FR-014)

### Implementation for User Story 3

- [ ] T029 [US3] Implement `Tokenization#revoke(reference, actor: nil)` → permanently invalidates the token (terminal `revoked`), in `lib/bml_tokenization/tokenization.rb` (depends on T012) — shares file with US1/US2, sequence edits
- [ ] T030 [US3] Enforce no-cascade in `revoke` (perform no calls that delete/mutate card-on-file or transaction resources), in `lib/bml_tokenization/tokenization.rb` (FR-005a)
- [ ] T031 [US3] Map unknown/already-revoked response to not-found/already-revoked error for `revoke`, in `lib/bml_tokenization/tokenization.rb` (FR-010, US3-2)
- [ ] T032 [US3] Emit `revoke` audit record (account + optional actor, token reference, outcome), in `lib/bml_tokenization/tokenization.rb` (FR-012)

**Checkpoint**: All three operations independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Cross-story hardening and validation.

- [ ] T033 [P] Cross-cutting leakage sweep test: assert NO full PAN/CVV/card-handle appears in any return value, `inspect`/`to_s`, structured log, or audit record across all three operations, in `spec/unit/no_leak_spec.rb` (FR-003, FR-012, FR-013, SC-002)
- [ ] T034 [P] Assert absence of any detokenize/reveal-PAN method on the public API (guards against regression), in `spec/contract/no_detokenization_spec.rb` (FR-006a, Clarification Q1)
- [ ] T035 [P] Add usage documentation for the tokenization resource (tokenize/retrieve/revoke, masked-only, no detokenization) in `README.md`
- [ ] T036 [P] Run dependency vulnerability scan (`bundle exec bundler-audit`) and confirm no secrets are committed (Constitution: dependencies tracked, secrets scanning)
- [ ] T037 Run `bundle exec rubocop` and resolve style/formatting across `lib/` and `spec/`
- [ ] T038 Execute `quickstart.md` validation scenarios V1–V12 and confirm all pass
- [ ] T039 [P] Environment-isolation test (credential-gated): assert a token reference issued in **sandbox** is reported not-found/invalid when the client is configured for **production** (and, where prod creds exist, the reverse), in `spec/integration/environment_isolation_sandbox_spec.rb` (FR-008, SC-005)
- [ ] T040 [P] Idempotency-isolation test (credential-gated): assert the same card handle tokenized under a **different account or environment** yields a **distinct, uncorrelated** token (complements the same-account/same-env "same token" check in T014/T018), in `spec/integration/tokenize_isolation_sandbox_spec.rb` (FR-011, SC-006)
- [ ] T041 [P] Token-strength inspection test: over a sample of issued/stubbed tokens, assert the token reference is **non-sequential** and shares **no derivable substring** with the PAN/last-four (the library neither generates nor shortens the token), in `spec/unit/token_strength_spec.rb`; if non-sequentiality is treated as a platform-owned guarantee, record that decision in `research.md` instead (FR-006, SC-007)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies — start immediately.
- **Foundational (Phase 2)**: depends on Setup — BLOCKS all user stories.
- **User Stories (Phases 3–5)**: all depend on Foundational (specifically the T012 resource skeleton
  and T011 `Token`). Each story is independently testable once Foundational is done.
- **Polish (Phase 6)**: depends on the stories being polished being complete.

### User Story Dependencies

- **US1 (P1)**: depends only on Foundational. No dependency on US2/US3.
- **US2 (P1)**: depends only on Foundational. Independently testable; shares `tokenization.rb` with US1/US3.
- **US3 (P2)**: depends only on Foundational. Independently testable; shares `tokenization.rb` with US1/US2.

### Within Each Story

- Tests (contract → unit → integration) written FIRST and must FAIL before implementation.
- Implementation: method → validation/error-mapping → audit/logging.
- Because all three operations edit `lib/bml_tokenization/tokenization.rb`, implementation tasks that
  touch that file are sequential across stories even though each story is independently testable.

### Parallel Opportunities

- Setup: T003 in parallel with T001/T002 review.
- Foundational tests T004, T005 in parallel; impl T007, T008, T009, T011 in parallel (distinct files),
  while T006→T010→T012 form the transport chain.
- All per-story **test** tasks are `[P]` (distinct spec files): T013/T014/T015, T020/T021/T022,
  T026/T027/T028.
- Polish T033, T034, T035, T036, T039, T040, T041 in parallel (distinct files).

---

## Parallel Example: User Story 1 tests

```bash
# Write these three failing specs together (distinct files):
Task: "Contract test for tokenize in spec/contract/tokenize_contract_spec.rb"
Task: "Unit test for tokenize validation + idempotency in spec/unit/tokenize_spec.rb"
Task: "Integration (sandbox) test for tokenize in spec/integration/tokenize_sandbox_spec.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 Setup → 2. Phase 2 Foundational (CRITICAL — blocks stories) → 3. Phase 3 US1.
4. **STOP and VALIDATE**: tokenize works end-to-end against sandbox with masked-only output.
5. Ship the MVP (tokenize + the shared foundation).

### Incremental Delivery

1. Setup + Foundational → foundation ready.
2. US1 (tokenize) → validate → ship MVP.
3. US2 (retrieve) → validate → ship.
4. US3 (revoke) → validate → ship.
5. Polish → leakage sweep, no-detokenization guard, environment/account isolation + token-strength
   checks, docs, audit scan, quickstart V1–V12.

### Notes

- `[P]` = different files, no incomplete dependencies.
- Verify each test fails before implementing (Constitution II).
- Never log/persist PAN/CVV/handle; every op emits an audit record with no card data.
- Commit after each task or logical group.
