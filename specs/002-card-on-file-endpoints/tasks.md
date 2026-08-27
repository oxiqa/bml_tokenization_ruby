---

description: "Task list for Card-on-File Endpoints"
---

# Tasks: Card-on-File Endpoints

**Input**: Design documents from `/specs/002-card-on-file-endpoints/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: INCLUDED — Constitution Principle II (Test-First) is NON-NEGOTIABLE and plan.md/quickstart.md
specify an RSpec, test-first strategy (contract + unit + opt-in sandbox integration). Every production
task is preceded by a failing test.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US4)
- Every task includes an exact file path

## Path Conventions

Single-project Ruby gem (per plan.md Structure Decision): library code under `lib/bml_tokenization/`,
specs under `spec/` at the repository root.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Gem project initialization and test tooling.

- [ ] T001 Create/verify the Ruby gem project structure at repo root: `bml_tokenization.gemspec`, `Gemfile`, `lib/bml_tokenization.rb` (entrypoint that requires the resource files, incl. the new card-on-file files), and the `lib/bml_tokenization/` and `spec/` directories per plan.md — reuse if a sibling feature (001/003/004) already created them
- [ ] T002 Ensure RSpec and WebMock are development dependencies (in `bml_tokenization.gemspec`/`Gemfile`) and that `.rspec` plus `spec/spec_helper.rb` load WebMock and disable real HTTP by default — reuse/verify if already present
- [ ] T003 [P] Ensure RuboCop linting/formatting is configured in `.rubocop.yml` at repo root — reuse/verify if already present

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared client/transport/error/logging/audit plumbing plus the cross-story `CardOnFile`
value object and resource skeleton that every user story depends on. These are shared per plan.md;
where sibling features (001/003/004) already provide `client.rb`/`errors.rb`/`resource.rb`/`masking.rb`,
verify and reuse rather than duplicate. The `transport` (timeout + bounded retry, FR-014) and `audit`
(state-change auditing, FR-015) concerns are first required by this feature.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T004 Establish/verify the shared configured `Client` (base URL, sandbox/production environment selection, credential/auth injection, TLS-only transport, configurable request timeout) in `lib/bml_tokenization/client.rb` (FR-008, FR-009, FR-014, Constitution I/III)
- [ ] T005 [P] Establish/extend the shared mapped error hierarchy — validation, not-found, conflict, authentication/config, **rate-limit**, and availability/timeout — in `lib/bml_tokenization/errors.rb` (FR-010, FR-014)
- [ ] T006 [P] Establish/verify base `Resource` HTTP/JSON request-response behavior (build request, parse JSON, dispatch to error mapping, route through the transport concern) in `lib/bml_tokenization/resource.rb`
- [ ] T007 [P] Establish/verify the shared masking + structured-logging concern (scrubs SAD/PAN, never logs the single-use handle; logs only safe reference/outcome) in `lib/bml_tokenization/masking.rb` (FR-003, Constitution IV)
- [ ] T008 [P] Write failing unit spec for the shared transport concern in `spec/unit/transport_spec.rb` — asserts a configurable timeout; bounded automatic retry (≤2, with backoff) on transient failures (connection error, timeout, 5xx); non-transient errors (validation, not-found, auth) are NOT retried; a 429 is retried honoring `Retry-After` and, if still limited, raises a distinguishable rate-limit error; retry-exhausted raises a distinguishable availability error with no partial result (FR-014, research R6/R7)
- [ ] T009 Implement the shared transport concern (timeout + bounded retry + rate-limit handling) in `lib/bml_tokenization/transport.rb` to pass T008, and route base `Resource` requests through it (depends on T008, T006)
- [ ] T010 [P] Write failing unit spec for the shared audit concern in `spec/unit/audit_spec.rb` — asserts a state-change audit record captures `action`, `card_reference`, `actor` (client identity + optional integrator actor), `occurred_at`, and `outcome`, and contains NO card data beyond the safe reference (FR-006a, FR-015, research R10)
- [ ] T011 Implement the shared audit concern in `lib/bml_tokenization/audit.rb` to pass T010 (depends on T010)
- [ ] T012 [P] Write failing unit spec for the `CardOnFile` value object in `spec/unit/card_on_file_spec.rb` — asserts fields `reference`, `customer_id`, `scheme`, `last_four`, `expiry_month`, `expiry_year`, `status`, `created_at`, and a derived `expired?`; asserts NO full PAN, CVV, single-use handle, or SAD attribute exists on the object or its serialization (data-model.md, FR-003)
- [ ] T013 Implement the `CardOnFile` value object in `lib/bml_tokenization/card_on_file.rb` to pass T012 (depends on T012)
- [ ] T014 Implement the `CardsOnFile` resource skeleton and the `client.cards_on_file` accessor (FR-001) in `lib/bml_tokenization/cards_on_file.rb` and register it on `lib/bml_tokenization/client.rb` (depends on T004, T006)

**Checkpoint**: Foundation ready — user stories can now proceed.

---

## Phase 3: User Story 1 - Store a card on file for a customer (Priority: P1) 🎯 MVP

**Goal**: An integrator can store a customer's card through `client.cards_on_file` by supplying a
single-use card handle and receive a `CardOnFile` with a safe reference and masked summary — never a
full card number — with re-storing the same card returning the existing record.

**Independent Test**: Store a card for a known customer with a valid single-use handle against sandbox
and confirm a `CardOnFile` with a safe reference + masked summary and no full card number; store the
same card again and confirm the existing record is returned (no duplicate); store missing a required
input and confirm a field-naming validation error with no network call.

### Tests for User Story 1 (write first, must FAIL before implementation)

- [ ] T015 [P] [US1] Contract test for store in `spec/contract/cards_on_file_api_spec.rb` — `client.cards_on_file` accessor exists (FR-001); `store(customer_id:, card_handle:)` returns a `CardOnFile` with a safe `reference` + masked summary and NO full card number (FR-002, FR-003); missing/blank `customer_id` or `card_handle` raises a validation error naming the input with NO network call (FR-007, SC-006); a re-store of an already-on-file card returns the existing record with no duplicate (FR-013); store emits a `store` audit record with no card data (FR-015)
- [ ] T016 [P] [US1] Remote contract test for the store endpoint in `spec/contract/cards_on_file_remote_spec.rb` — WebMock stub asserts the request body carries only `customer_id` + `card_handle` and NO PAN/CVV/SAD; a response indicating already-on-file (200/201/409-with-reference) is normalized to an idempotent success returning the existing reference (FR-013); maps invalid/consumed/expired handle→validation, unknown customer→not-found/validation, auth→auth, 429→rate-limit, timeout/5xx→availability (contracts/bml-remote.md)
- [ ] T017 [P] [US1] Unit test for store local validation, idempotency normalization, and audit emission in `spec/unit/cards_on_file_spec.rb` — required-input validation runs before any remote call; duplicate is normalized to an idempotent return; a `store` audit record is emitted; the single-use handle never appears in output or logs

### Implementation for User Story 1

- [ ] T018 [US1] Implement `store` in `lib/bml_tokenization/cards_on_file.rb` — validate `customer_id` + `card_handle` before the remote call, POST via the base `Resource`/transport, build a `CardOnFile` from the response, normalize an already-on-file result to an idempotent success, emit a `store` audit record (with optional `actor:`), and map remote errors (depends on T015–T017)
- [ ] T019 [US1] Add an opt-in, credential-gated sandbox integration test for store (including environment isolation and idempotent re-store) in `spec/integration/cards_on_file_sandbox_spec.rb` (FR-012, US1-3, SC-005, FR-013)

**Checkpoint**: Store works end-to-end and is independently testable (MVP).

---

## Phase 4: User Story 2 - List a customer's cards on file (Priority: P1)

**Goal**: An integrator can enumerate all of a customer's stored cards, each represented only by a
safe reference and masked summary.

**Independent Test**: Store one or more cards for a customer, list them, and confirm each appears with
a safe reference and masked summary; list a customer with no cards and confirm an empty list (not an
error).

### Tests for User Story 2 (write first, must FAIL before implementation)

- [ ] T020 [P] [US2] Unit test for the `CardOnFileList` value object in `spec/unit/card_on_file_list_spec.rb` — asserts `customer_id` and `records` (each a `CardOnFile`), that an empty `records` set is valid (not an error), and that no pagination fields are required (data-model.md, R11)
- [ ] T021 [P] [US2] Contract test for list in `spec/contract/cards_on_file_api_spec.rb` — `list(customer_id:)` returns a `CardOnFileList` containing all the customer's cards with safe reference + masked summary (FR-004); a customer with no cards yields an empty list, not an error (US2-2); list emits NO audit record (FR-015)
- [ ] T022 [P] [US2] Remote contract test for the list endpoint in `spec/contract/cards_on_file_remote_spec.rb` — WebMock stub asserts no pagination params are sent and that an empty `data` array yields an empty `CardOnFileList` (contracts/bml-remote.md)

### Implementation for User Story 2

- [ ] T023 [US2] Implement the `CardOnFileList` value object (`customer_id`, `records`) in `lib/bml_tokenization/card_on_file_list.rb` to pass T020 (depends on T020)
- [ ] T024 [US2] Implement `list` in `lib/bml_tokenization/cards_on_file.rb` — validate `customer_id`, GET via the base `Resource`/transport, build a `CardOnFileList`, honor empty-list semantics, emit no audit record (depends on T021, T022, T023; shares file with T018)
- [ ] T025 [US2] Add an opt-in, credential-gated sandbox integration test for list (store-then-list, and empty-list) in `spec/integration/cards_on_file_sandbox_spec.rb` (FR-012, US2-1, US2-2)

**Checkpoint**: Store + list both work independently (P1 core complete).

---

## Phase 5: User Story 3 - Retrieve a single card on file (Priority: P2)

**Goal**: An integrator can look up a single stored card by its safe reference and read its current
masked summary, scheme, and expiry/validity status.

**Independent Test**: Store a card, retrieve it by its reference, confirm the masked summary matches
and expiry/validity is discoverable; retrieve an unknown reference and confirm a not-found error.

### Tests for User Story 3 (write first, must FAIL before implementation)

- [ ] T026 [P] [US3] Contract test for retrieve in `spec/contract/cards_on_file_api_spec.rb` — `retrieve(reference)` returns the current `CardOnFile` with masked summary and discoverable expiry/validity (`expired?`) (FR-005, edge case); an unknown reference raises a not-found error (US3-2); retrieve emits NO audit record (FR-015)
- [ ] T027 [P] [US3] Remote contract test for the retrieve endpoint in `spec/contract/cards_on_file_remote_spec.rb` — WebMock stub maps 404→not-found and auth failure→auth, and asserts the response carries only masked data (no full PAN) (contracts/bml-remote.md)

### Implementation for User Story 3

- [ ] T028 [US3] Implement `retrieve(reference)` in `lib/bml_tokenization/cards_on_file.rb` — GET via the base `Resource`/transport, build a `CardOnFile`, map not-found/auth errors, emit no audit record (depends on T026, T027; shares file with T018/T024)
- [ ] T029 [US3] Add an opt-in, credential-gated sandbox integration test for retrieve (store-then-retrieve round-trip; expiry discoverable) in `spec/integration/cards_on_file_sandbox_spec.rb` (FR-012, US3-1)

**Checkpoint**: Store + list + retrieve all work independently.

---

## Phase 6: User Story 4 - Remove a card on file (Priority: P2)

**Goal**: An integrator can permanently delete a saved card so it can no longer be used, with a
card-data-free audit record retained.

**Independent Test**: Store a card, remove it, and confirm it no longer appears in the customer's list
and retrieval returns not-found; remove an unknown/already-removed reference and confirm a not-found
error with no other card affected; confirm a `remove` audit record (no card data) is emitted.

### Tests for User Story 4 (write first, must FAIL before implementation)

- [ ] T030 [P] [US4] Contract test for remove in `spec/contract/cards_on_file_api_spec.rb` — `remove(reference)` permanently deletes the card (afterward retrieval returns not-found and it is absent from the customer's list; not recoverable) (FR-006, US4-1, SC-004); an already-removed or unknown reference raises a not-found error with no other card affected (US4-2); remove emits a `remove` audit record with no card data beyond the safe reference (FR-006a, FR-015)
- [ ] T031 [P] [US4] Remote contract test for the remove endpoint in `spec/contract/cards_on_file_remote_spec.rb` — WebMock stub asserts a delete request and maps an unknown/already-removed reference (404)→not-found and auth failure→auth (contracts/bml-remote.md)

### Implementation for User Story 4

- [ ] T032 [US4] Implement `remove(reference)` in `lib/bml_tokenization/cards_on_file.rb` — DELETE via the base `Resource`/transport, confirm permanent removal, emit a `remove` audit record (with optional `actor:`) carrying no card data, and map not-found/auth errors (depends on T030, T031; shares file with T018/T024/T028)
- [ ] T033 [US4] Add an opt-in, credential-gated sandbox integration test for remove (store→remove→confirm gone from list and retrieval) in `spec/integration/cards_on_file_sandbox_spec.rb` (FR-012, US4-1, SC-004)

**Checkpoint**: All four operations work independently.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Cross-cutting guarantees spanning all operations and final validation.

- [ ] T034 [P] Cross-cutting unit test asserting no full PAN, CVV, single-use handle, or SAD appears in any output, error, or log across all four operations in `spec/unit/cards_on_file_spec.rb` (FR-003, SC-002)
- [ ] T035 [P] Cross-cutting test asserting environment isolation — sandbox vs production route to the configured base URL and never cross — in `spec/contract/cards_on_file_remote_spec.rb` (FR-008, SC-005)
- [ ] T036 [P] Cross-cutting resilience test asserting transient-failure retry-then-succeed, retry-exhausted→distinguishable availability error (no partial record), and 429→retry honoring `Retry-After`→distinguishable rate-limit error, across operations in `spec/contract/cards_on_file_remote_spec.rb` (FR-014, edge cases)
- [ ] T037 [P] Cross-cutting audit test asserting `store` and `remove` emit an audit record (who/what/when/outcome, no card data) while `list` and `retrieve` emit none, in `spec/unit/cards_on_file_spec.rb` (FR-006a, FR-015)
- [ ] T038 Wire structured logging (operation, customer id, card safe reference, outcome, timing) through the masking concern across all operations in `lib/bml_tokenization/cards_on_file.rb` (FR-003, Constitution IV)
- [ ] T039 [P] Add cards-on-file usage documentation (store with a single-use handle, list, retrieve, remove; idempotent re-store; permanent removal; configurable timeout + retry; audit on state changes) to `README.md`
- [ ] T040 Run the `quickstart.md` validation scenarios V1–V20 and confirm the deterministic suite is green (and the sandbox suite where credentials + a handle are provided)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories.
- **User Stories (Phase 3–6)**: All depend on Foundational. In priority order US1 → US2 → US3 → US4;
  they may also proceed in parallel by different developers, but US2/US3/US4 each add a method to the
  same `lib/bml_tokenization/cards_on_file.rb`, so their implementation tasks serialize on that file.
- **Polish (Phase 7)**: Depends on the user stories it covers being complete.

### User Story Dependencies

- **US1 (P1)**: Foundational only. No dependency on other stories. Uses `CardOnFile` + `transport` + `audit`.
- **US2 (P1)**: Foundational only. Adds its own `CardOnFileList`; independently testable.
- **US3 (P2)**: Foundational only. Reuses `CardOnFile`; independently testable.
- **US4 (P2)**: Foundational only. Reuses `audit`; independently testable.

### Within Each User Story

- Tests are written first and MUST FAIL before implementation (Constitution II).
- Value objects/models and shared concerns before the resource methods that use them.
- Local input validation before the remote call in every operation.

### Parallel Opportunities

- Setup: T003 is [P] alongside T001/T002 ordering.
- Foundational: T005, T006, T007 are [P] (distinct files); T008/T010/T012 test-writing are [P]; T009 depends on T008/T006, T011 on T010, T013 on T012; T014 depends on T004/T006.
- Within a story, the test tasks marked [P] target distinct spec files and run together; the single
  implementation task per story then follows.
- Across stories: once Foundational is done, US1–US4 test-writing can proceed in parallel; the
  implementation methods serialize on `cards_on_file.rb`.

---

## Parallel Example: User Story 1

```bash
# Write all US1 tests together (distinct spec files), confirm they FAIL:
Task: "Contract test for store in spec/contract/cards_on_file_api_spec.rb"
Task: "Remote contract test for store in spec/contract/cards_on_file_remote_spec.rb"
Task: "Unit test for store validation/idempotency/audit in spec/unit/cards_on_file_spec.rb"
# Then implement:
Task: "Implement store in lib/bml_tokenization/cards_on_file.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Complete Phase 1 (Setup) and Phase 2 (Foundational).
2. Complete Phase 3 (US1 — store).
3. **STOP and VALIDATE**: store works end-to-end against sandbox, returns a safe reference + masked
   summary with no full card number, and re-store is idempotent (SC-001, SC-002, FR-013).

### Incremental Delivery

1. Setup + Foundational → foundation ready.
2. US1 (store) → validate → MVP.
3. US2 (list) → validate → P1 core complete.
4. US3 (retrieve) → validate.
5. US4 (remove) → validate.
6. Polish → cross-cutting guarantees (no-leakage, env isolation, resilience, audit) + quickstart validation.

### Parallel Team Strategy

After Foundational, developers can pick up US1–US4 in parallel; coordinate on `cards_on_file.rb` since
each story adds a method there, or extract per-operation modules if working truly concurrently.

---

## Notes

- [P] = different files, no dependencies on incomplete tasks.
- [Story] label maps each task to its user story for traceability.
- Every production task is preceded by a failing test (Constitution II, NON-NEGOTIABLE).
- No task accepts, stores, or logs a raw PAN, CVV, or the single-use handle (Constitution I, FR-002, FR-003).
- State-changing operations (store, remove) emit a card-data-free audit record; reads do not (FR-006a, FR-015).
- Commit after each task or logical group; stop at any checkpoint to validate a story independently.
