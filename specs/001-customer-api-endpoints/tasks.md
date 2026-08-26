---

description: "Task list for Customer API Endpoints"
---

# Tasks: Customer API Endpoints

**Input**: Design documents from `/specs/001-customer-api-endpoints/`

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

- [ ] T001 Create the Ruby gem project structure at repo root: `bml_tokenization.gemspec`, `Gemfile`, `lib/bml_tokenization.rb` (entrypoint that requires the resource files), and empty `lib/bml_tokenization/` and `spec/` directories per plan.md
- [ ] T002 Add RSpec and WebMock as development dependencies (in `bml_tokenization.gemspec`/`Gemfile`) and create `.rspec` plus `spec/spec_helper.rb` that loads WebMock and disables real HTTP by default
- [ ] T003 [P] Configure RuboCop for linting/formatting in `.rubocop.yml` at repo root

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared client/transport/error/logging plumbing plus the cross-story `Customer` value
object that every user story depends on. These are shared per plan.md; where sibling features
(002/003/004) already provide `client.rb`/`errors.rb`/`resource.rb`/`masking.rb`, verify and reuse
rather than duplicate.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T004 Establish the shared configured `Client` (base URL, sandbox/production environment selection, credential/auth injection, TLS-only transport) in `lib/bml_tokenization/client.rb` — verify/reuse if already provided by sibling features (FR-007, FR-008, Constitution I/III)
- [ ] T005 [P] Establish the shared mapped error hierarchy — validation, not-found, conflict, authentication/config, availability/timeout — in `lib/bml_tokenization/errors.rb` (FR-009)
- [ ] T006 [P] Establish base `Resource` HTTP/JSON request-response behavior (build request, parse JSON, dispatch to error mapping) in `lib/bml_tokenization/resource.rb`
- [ ] T007 [P] Establish the shared masking + structured-logging concern (scrubs SAD/PAN, minimizes customer PII) in `lib/bml_tokenization/masking.rb` (FR-010, Constitution IV)
- [ ] T008 [P] Write failing unit spec for the `Customer` value object in `spec/unit/customer_spec.rb` — asserts fields `id`, `first_name`, `last_name`, `email`, `phone`, `reference`, `created_at`, `updated_at`, and asserts NO SAD/PAN attribute exists on the object or its serialization (data-model.md, FR-010)
- [ ] T009 Implement the `Customer` value object in `lib/bml_tokenization/customer.rb` to pass T008 (depends on T008)
- [ ] T010 Implement the `Customers` resource skeleton and the `client.customers` accessor (FR-001) in `lib/bml_tokenization/customers.rb` and register it on `lib/bml_tokenization/client.rb` (depends on T004, T006)

**Checkpoint**: Foundation ready — user stories can now proceed.

---

## Phase 3: User Story 1 - Create a customer (Priority: P1) 🎯 MVP

**Goal**: An integrator can register a customer through `client.customers` and receive a persisted
`Customer` with a platform-assigned identifier.

**Independent Test**: Call create with valid `first_name`/`last_name`/`email` against sandbox and
confirm a `Customer` with an `id` is returned; call create missing a required field and confirm a
field-naming validation error with no network call.

### Tests for User Story 1 (write first, must FAIL before implementation)

- [ ] T011 [P] [US1] Contract test for create in `spec/contract/customers_api_spec.rb` — `client.customers` accessor exists (FR-001); `create(details)` returns a `Customer` with `id` + submitted details (FR-002); missing/blank `first_name`, `last_name`, or `email` raises a validation error naming the field with NO network call (FR-006, SC-003)
- [ ] T012 [P] [US1] Remote contract test for the create endpoint in `spec/contract/customers_remote_spec.rb` — WebMock stub asserts request body carries `first_name`/`last_name`/`email`/`phone`/`reference` and NO card data; maps duplicate→conflict, auth→auth, timeout/5xx→availability (contracts/bml-remote.md)
- [ ] T013 [P] [US1] Unit test for create local validation and error mapping in `spec/unit/customers_spec.rb` — required-field validation runs before any remote call; each mapped error type is distinguishable

### Implementation for User Story 1

- [ ] T014 [US1] Implement `create` in `lib/bml_tokenization/customers.rb` — validate required fields (`first_name`, `last_name`, `email`) before the remote call, POST via the base `Resource`, build a `Customer` from the response, and map remote errors (depends on T011–T013)
- [ ] T015 [US1] Add an opt-in, credential-gated sandbox integration test for create (including environment isolation) in `spec/integration/customers_sandbox_spec.rb` (FR-011, US1-3, SC-005)

**Checkpoint**: Create works end-to-end and is independently testable (MVP).

---

## Phase 4: User Story 2 - Retrieve a customer by identifier (Priority: P1)

**Goal**: An integrator can look up a single customer by its identifier and receive the current record.

**Independent Test**: Create a customer, retrieve it by `id`, confirm details match; retrieve an
unknown identifier and confirm a not-found error.

### Tests for User Story 2 (write first, must FAIL before implementation)

- [ ] T016 [P] [US2] Contract test for retrieve in `spec/contract/customers_api_spec.rb` — `retrieve(id)` returns the current `Customer` (FR-003); an unknown identifier raises a not-found error (US2-2)
- [ ] T017 [P] [US2] Remote contract test for the get endpoint in `spec/contract/customers_remote_spec.rb` — WebMock stub maps 404→not-found and auth failure→auth (contracts/bml-remote.md)

### Implementation for User Story 2

- [ ] T018 [US2] Implement `retrieve(id)` in `lib/bml_tokenization/customers.rb` — GET via the base `Resource`, build a `Customer`, map not-found/auth errors (depends on T016, T017; shares file with T014)
- [ ] T019 [US2] Add an opt-in, credential-gated sandbox integration test for retrieve (create-then-retrieve round-trip) in `spec/integration/customers_sandbox_spec.rb` (FR-011)

**Checkpoint**: Create + retrieve both work independently (P1 core complete).

---

## Phase 5: User Story 3 - List customers (Priority: P2)

**Goal**: An integrator can browse customers using page-number pagination, receiving a bounded page
of records.

**Independent Test**: Create several customers, list with `page`/`page_size`, confirm a page of
results; list when none exist and beyond the last page and confirm an empty page (not an error);
request `page_size` > 100 and confirm a field-naming validation error with no network call.

### Tests for User Story 3 (write first, must FAIL before implementation)

- [ ] T020 [P] [US3] Unit test for the `CustomerListPage` value object in `spec/unit/customer_list_page_spec.rb` — empty `records` for none/beyond-range (not an error), `page`/`page_size` echoed back, `has_next`/`next_page` on non-final pages, and `page_size` > 100 rejected (data-model.md, R4)
- [ ] T021 [P] [US3] Contract test for list in `spec/contract/customers_api_spec.rb` — `list(page:, page_size:)` returns a `CustomerListPage`; `page_size` defaults to 20; `page_size` > 100 raises a validation error naming `page_size` with NO network call (FR-004, FR-006); empty-page semantics hold
- [ ] T022 [P] [US3] Remote contract test for the list endpoint in `spec/contract/customers_remote_spec.rb` — WebMock stub asserts page-number params are sent and an empty `data` array yields an empty page (contracts/bml-remote.md)

### Implementation for User Story 3

- [ ] T023 [US3] Implement the `CustomerListPage` value object (`records`, `page`, `page_size`, `has_next`/`next_page`) in `lib/bml_tokenization/customer_list_page.rb` to pass T020 (depends on T020)
- [ ] T024 [US3] Implement `list` in `lib/bml_tokenization/customers.rb` — apply `page`/`page_size` defaults (20) and cap (reject `page_size` > 100 before the remote call), GET via the base `Resource`, build a `CustomerListPage`, honor empty-page semantics (depends on T021, T022, T023; shares file with T014/T018)
- [ ] T025 [US3] Add an opt-in, credential-gated sandbox integration test for list + pagination in `spec/integration/customers_sandbox_spec.rb` (FR-011, US3-2)

**Checkpoint**: Create + retrieve + list all work independently.

---

## Phase 6: User Story 4 - Update a customer (Priority: P3)

**Goal**: An integrator can replace a customer's mutable details using full-replace semantics.

**Independent Test**: Create a customer, update it with a complete valid record, retrieve and confirm
the change (and that fields omitted from the record are cleared); update with a missing/invalid
required field and confirm a field-naming validation error with the customer unchanged.

### Tests for User Story 4 (write first, must FAIL before implementation)

- [ ] T026 [P] [US4] Contract test for update in `spec/contract/customers_api_spec.rb` — `update(id, record)` uses full-replace (complete record required; omitted mutable fields cleared); missing/invalid required field raises a validation error naming the field with NO network call and the customer unchanged (FR-005, FR-006, US4-2); unknown id → not-found
- [ ] T027 [P] [US4] Remote contract test for the update endpoint in `spec/contract/customers_remote_spec.rb` — WebMock stub asserts the complete record is sent and maps 404→not-found, invalid field→validation (contracts/bml-remote.md, R9)

### Implementation for User Story 4

- [ ] T028 [US4] Implement `update(id, record)` with full-replace semantics in `lib/bml_tokenization/customers.rb` — reuse the required-field validation from create, send the complete record, build a `Customer`, map not-found/validation/auth errors (depends on T026, T027; shares file with T014/T018/T024)
- [ ] T029 [US4] Add an opt-in, credential-gated sandbox integration test for update (full-replace round-trip) in `spec/integration/customers_sandbox_spec.rb` (FR-011, US4-1)

**Checkpoint**: All four operations work independently.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Cross-cutting guarantees spanning all operations and final validation.

- [ ] T030 [P] Cross-cutting unit test asserting no SAD/PAN or full card number appears in any output, error, or log across all four operations in `spec/unit/customers_spec.rb` (FR-010, SC-004)
- [ ] T031 [P] Cross-cutting test asserting environment isolation — sandbox vs production route to the configured base URL and never cross — in `spec/contract/customers_remote_spec.rb` (FR-007, SC-005)
- [ ] T032 [P] Cross-cutting test asserting auth/config and availability/timeout error mapping (no partial record on timeout; distinguishable types) in `spec/contract/customers_remote_spec.rb` (FR-008, FR-009, edge cases)
- [ ] T033 Wire structured logging (operation, customer id, outcome, timing) through the masking concern across all operations in `lib/bml_tokenization/customers.rb` (FR-010, Constitution IV)
- [ ] T034 [P] Add customer-resource usage documentation (create/retrieve/list/update, pagination, full-replace update) to `README.md`
- [ ] T035 Run the `quickstart.md` validation scenarios V1–V15 and confirm the deterministic suite is green (and the sandbox suite where credentials are provided)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories.
- **User Stories (Phase 3–6)**: All depend on Foundational. In priority order US1 → US2 → US3 → US4;
  they may also proceed in parallel by different developers, but US2/US3/US4 each add a method to the
  same `lib/bml_tokenization/customers.rb`, so their implementation tasks serialize on that file.
- **Polish (Phase 7)**: Depends on the user stories it covers being complete.

### User Story Dependencies

- **US1 (P1)**: Foundational only. No dependency on other stories.
- **US2 (P1)**: Foundational only. Independently testable (uses shared `Customer`).
- **US3 (P2)**: Foundational only. Adds its own `CustomerListPage`; independently testable.
- **US4 (P3)**: Foundational only. Reuses create's validation helper; independently testable.

### Within Each User Story

- Tests are written first and MUST FAIL before implementation (Constitution II).
- Value objects/models before the resource methods that build them.
- Local validation before the remote call in every operation.

### Parallel Opportunities

- Setup: T003 is [P] alongside T001/T002 ordering.
- Foundational: T005, T006, T007, T008 are [P] (distinct files); T009 depends on T008; T010 depends on T004/T006.
- Within a story, the test tasks marked [P] target distinct spec files and run together; the single
  implementation task per story then follows.
- Across stories: once Foundational is done, US1–US4 test-writing can proceed in parallel; the
  implementation methods serialize on `customers.rb`.

---

## Parallel Example: User Story 1

```bash
# Write all US1 tests together (distinct spec files), confirm they FAIL:
Task: "Contract test for create in spec/contract/customers_api_spec.rb"
Task: "Remote contract test for create in spec/contract/customers_remote_spec.rb"
Task: "Unit test for create validation in spec/unit/customers_spec.rb"
# Then implement:
Task: "Implement create in lib/bml_tokenization/customers.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Complete Phase 1 (Setup) and Phase 2 (Foundational).
2. Complete Phase 3 (US1 — create).
3. **STOP and VALIDATE**: create works end-to-end against sandbox (SC-001).

### Incremental Delivery

1. Setup + Foundational → foundation ready.
2. US1 (create) → validate → MVP.
3. US2 (retrieve) → validate → P1 core complete.
4. US3 (list) → validate.
5. US4 (update) → validate.
6. Polish → cross-cutting guarantees + quickstart validation.

### Parallel Team Strategy

After Foundational, developers can pick up US1–US4 in parallel; coordinate on `customers.rb` since
each story adds a method there, or extract per-operation modules if working truly concurrently.

---

## Notes

- [P] = different files, no dependencies on incomplete tasks.
- [Story] label maps each task to its user story for traceability.
- Every production task is preceded by a failing test (Constitution II, NON-NEGOTIABLE).
- No task accepts, stores, or logs card data or SAD (Constitution I, FR-010).
- Commit after each task or logical group; stop at any checkpoint to validate a story independently.
