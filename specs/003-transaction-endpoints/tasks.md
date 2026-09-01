---

description: "Task list for Transaction Endpoints implementation"
---

# Tasks: Transaction Endpoints

**Input**: Design documents from `/specs/003-transaction-endpoints/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ (all present)

**Tests**: Test tasks are **INCLUDED and REQUIRED** — Constitution Principle II (Test-First) is
NON-NEGOTIABLE and the spec mandates independent testability (FR-011, SC-002). Every contract/unit
test MUST be written first and MUST fail before its implementation task.

**Organization**: Tasks are grouped by user story (US1 Create, US2 Retrieve, US3 List) so each story
is independently implementable and testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1 / US2 / US3 (Setup, Foundational, Polish carry no story label)

## Path Conventions

Single-project Ruby gem (per plan.md): library code in `lib/bml_tokenization/`, tests in `spec/`.
Shared scaffolding (`client`, `errors`, `resource`, `masking`, `transport`, `audit`) is reused from
`001`/`002`; where it does not yet exist in this repo it is created in the Foundational phase.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Gem project initialization and tooling

- [X] T001 Create/verify the gem structure per plan.md: `lib/bml_tokenization.rb` entry point,
  `lib/bml_tokenization/` and `spec/{contract,unit,integration}/` directories, `bml_tokenization.gemspec`,
  and `Gemfile`
- [X] T002 Configure RSpec and WebMock for deterministic HTTP stubbing in `spec/spec_helper.rb` and `.rspec`
- [X] T003 [P] Configure RuboCop (style/lint) in `.rubocop.yml`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared client, error, transport, masking, and audit concerns that ALL transaction
operations depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Ensure the shared configured `Client` (base URL, environment sandbox/production, TLS, auth
  headers) exposes a `transactions` accessor returning the Transactions resource, in
  `lib/bml_tokenization/client.rb` (FR-001, FR-007, FR-008)
- [X] T005 [P] Ensure the shared error hierarchy defines distinguishable `ValidationError`,
  `NotFoundError`, `ConflictError`, `AuthenticationError`, and `AvailabilityError` (add `ConflictError`
  if absent — new for this feature) in `lib/bml_tokenization/errors.rb` (FR-009, R10)
- [X] T006 [P] Ensure the shared base `Resource` behavior (client wiring, request helper) exists in
  `lib/bml_tokenization/resource.rb`
- [X] T007 [P] Ensure the shared masking helper scrubs any PAN/CVV and treats the hosted payment URL as
  a secret (never logged verbatim) in `lib/bml_tokenization/masking.rb` (FR-010, R11)
- [X] T008 Ensure the shared `transport` concern performs requests within a configurable timeout with
  bounded automatic retry (≤2, backoff) on connection error/`5xx`/timeout and honors `Retry-After` on
  `429`, mapping exhausted failures to `AvailabilityError`, in `lib/bml_tokenization/transport.rb` (R2)
- [X] T009 [P] Ensure the shared `audit` concern emits a structured audit record (who/what/when/outcome)
  with no card data and no payment URL in `lib/bml_tokenization/audit.rb` (FR-012, R11)

**Checkpoint**: Foundation ready — Transactions resource operations can now be built.

---

## Phase 3: User Story 1 - Create a transaction (Priority: P1) 🎯 MVP

**Goal**: An integrator creates a payment for an existing customer, receiving either a hosted payment
URL (redirect path) or a server-side charge result (stored-card path), with local validation,
idempotent-replay, and idempotency-conflict semantics.

**Independent Test**: Call `create` against sandbox with valid MVR details and no card → get a
`pending` transaction with a `payment_url`; call again with the same reference → get the same
transaction (no second charge); call with a differing amount on that reference → get a conflict error.

### Tests for User Story 1 (write first, must fail) ⚠️

- [X] T010 [P] [US1] Public-API contract test for `create` (both paths, required-field validation,
  MVR-only, amount rules, return-URL rule, idempotent replay, conflict) in
  `spec/contract/transactions_api_spec.rb` per `contracts/library-api.md`
- [X] T011 [P] [US1] Remote HTTP contract test for `POST /transactions` (redirect + stored-card request
  shapes, `201` responses, `409` conflict, error mapping) using WebMock stubs in
  `spec/contract/transactions_remote_spec.rb` per `contracts/bml-remote.md`
- [X] T012 [P] [US1] Unit tests for create validation and idempotency in `spec/unit/transactions_spec.rb`
  (missing customer/amount/currency/reference; non-integer/zero/negative amount; non-MVR currency;
  missing return_url on redirect path; identical replay returns existing; differing-parameter reuse →
  conflict; global reference scope across customers) (FR-005, FR-005a–c, FR-013)
- [X] T013 [P] [US1] Unit tests for the `Transaction` entity in `spec/unit/transaction_spec.rb` (four
  statuses; `payment_url` present only on redirect path; `card_reference` only on stored-card path;
  no full PAN/CVV field anywhere) (FR-006, FR-010, R6)
- [X] T014 [P] [US1] Opt-in, credential-gated sandbox integration test for create in
  `spec/integration/transactions_sandbox_spec.rb` (skips cleanly without credentials) (FR-011)

### Implementation for User Story 1

- [X] T015 [P] [US1] Implement the `Transaction` value object (id, reference, customer_id, amount,
  currency, normalized `status` enum, optional payment_url/card_reference/return_url/created_at; no
  PAN/CVV) in `lib/bml_tokenization/transaction.rb` (data-model.md)
- [X] T016 [US1] Implement pre-remote create validation (presence → amount integer/positive → currency
  == MVR → return_url required when no card_reference) raising `ValidationError` naming the field, with
  no network call on failure, in `lib/bml_tokenization/transactions.rb` (FR-005, FR-005a–c, FR-002)
- [X] T017 [US1] Implement `Transactions#create` selecting the redirect vs stored-card path by
  presence of `card_reference`, calling the shared transport and mapping the response to a
  `Transaction`, in `lib/bml_tokenization/transactions.rb` (depends on T015, T016, T004, T008) (FR-002)
- [X] T018 [US1] Implement idempotency + conflict handling on the global `reference`: identical replay
  returns the existing transaction (no second charge); differing material parameters raise
  `ConflictError` naming the mismatch, in `lib/bml_tokenization/transactions.rb` (depends on T017, T005)
  (FR-013, SC-007)
- [X] T019 [US1] Map remote create errors to the shared hierarchy (400→validation, 404→missing
  customer/not-found, 409→conflict, 401/403→auth, 429/5xx/timeout→availability) in
  `lib/bml_tokenization/transactions.rb` (depends on T017, T005) (FR-009, R10)
- [X] T020 [US1] Emit a `create` audit record (who = client identity + optional `actor`; what = create
  + id/reference; when; outcome) with no card data and no payment URL, in
  `lib/bml_tokenization/transactions.rb` (depends on T017, T009) (FR-012)

**Checkpoint**: User Story 1 is fully functional and independently testable (create MVP).

---

## Phase 4: User Story 2 - Retrieve a transaction by identifier (Priority: P1)

**Goal**: An integrator looks up a transaction by id to learn its current status (pending/succeeded/
failed/cancelled).

**Independent Test**: Create a transaction, then `retrieve(id)` and confirm the returned status and
details match; retrieve an unknown id and confirm a not-found error.

### Tests for User Story 2 (write first, must fail) ⚠️

- [X] T021 [US2] Add public-API + remote contract tests for `retrieve` (`GET /transactions/{id}`:
  current record with normalized status; unknown id → not-found; auth/availability mapping) in
  `spec/contract/transactions_api_spec.rb` and `spec/contract/transactions_remote_spec.rb`
  (US2-1, US2-2)
- [X] T022 [US2] Add retrieve unit tests (status distinguishable incl. `pending`; not-found on unknown
  id) in `spec/unit/transactions_spec.rb` (FR-003, FR-006)

### Implementation for User Story 2

- [X] T023 [US2] Implement `Transactions#retrieve(id)` returning the current `Transaction` with
  normalized status, mapping unknown id → `NotFoundError`, in `lib/bml_tokenization/transactions.rb`
  (depends on T017) (FR-003, FR-006)
- [X] T024 [US2] Emit a `retrieve` audit record (who/what/when/outcome, no card data) in
  `lib/bml_tokenization/transactions.rb` (depends on T023, T009) (FR-012)

**Checkpoint**: User Stories 1 AND 2 both work independently (create + confirm outcome).

---

## Phase 5: User Story 3 - List transactions (Priority: P2)

**Goal**: An integrator browses/reconciles transactions in pages, optionally filtered by customer
and/or status.

**Independent Test**: Create several transactions, then `list` and confirm a page is returned;
filter by customer and by status and confirm only matching records; request page size 101 and confirm
rejection; request a page beyond the results and confirm an empty page.

### Tests for User Story 3 (write first, must fail) ⚠️

- [X] T025 [US3] Add public-API + remote contract tests for `list` (page-number pagination; default 20
  / reject `page_size` > 100; optional combinable customer/status filters; unknown status → validation
  error; empty/out-of-range page → empty page, not error) in `spec/contract/transactions_api_spec.rb`
  and `spec/contract/transactions_remote_spec.rb` (US3-1..US3-5, FR-004)
- [X] T026 [P] [US3] Unit tests for the `TransactionList` page in `spec/unit/transaction_list_spec.rb`
  (records/page/page_size/total_count; default 20; max 100; empty page is not an error) (FR-004, R7)

### Implementation for User Story 3

- [X] T027 [P] [US3] Implement the `TransactionList` value object (records + page/page_size/total_count
  metadata) in `lib/bml_tokenization/transaction_list.rb` (data-model.md)
- [X] T028 [US3] Implement `Transactions#list` with page-number pagination (default 20) and optional
  `customer_id`/`status` filters, mapping the response to a `TransactionList`, in
  `lib/bml_tokenization/transactions.rb` (depends on T027, T017) (FR-004)
- [X] T029 [US3] Enforce list validation: reject `page_size` > 100 and unrecognized `status` filter
  locally with `ValidationError`; return an empty page (not an error) when no records match, in
  `lib/bml_tokenization/transactions.rb` (depends on T028) (FR-004, R7)

**Checkpoint**: All three user stories are independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Guarantees that span all operations

- [X] T030 [P] Add a leakage-inspection unit test asserting no full PAN/CVV and no hosted payment URL
  appears in any output, error, or log across create/retrieve/list, in `spec/unit/transactions_spec.rb`
  (FR-010, SC-005, R11)
- [X] T031 [P] Document Transactions usage (both create paths, idempotency/conflict, list filters) in
  the gem README / `docs/`
- [X] T032 Run the `quickstart.md` validation scenarios V1–V27 (deterministic suite green; sandbox
  suite green where credentials are provided) and confirm SC-001..SC-007
- [X] T033 [P] RuboCop clean-up and refactor for consistency with sibling resources

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **User Stories (Phase 3–5)**: All depend on Foundational completion
  - US1 (P1) and US2 (P1) and US3 (P2) can then proceed in parallel by different developers, or
    sequentially in priority order (US1 → US2 → US3)
- **Polish (Phase 6)**: Depends on the targeted user stories being complete

### User Story Dependencies

- **US1 (Create, P1)**: Only depends on Foundational. Creates `transactions.rb` and `transaction.rb`.
- **US2 (Retrieve, P1)**: Depends on Foundational; shares `transactions.rb` with US1 (its impl tasks
  append to the same file, so run after US1's `transactions.rb` exists or coordinate edits). Testable
  independently once `retrieve` is implemented.
- **US3 (List, P2)**: Depends on Foundational; adds `transaction_list.rb` and a `list` method to
  `transactions.rb`. Testable independently.

### Within Each User Story

- Tests (Constitution II) MUST be written and FAIL before implementation
- Entity/value objects before the service methods that build them
- Core method before its idempotency/audit/error-mapping refinements
- Story complete before moving to the next priority

### Parallel Opportunities

- Setup: T003 in parallel with T001/T002
- Foundational: T005, T006, T007, T009 in parallel (distinct files); T004 and T008 after their deps
- US1 tests T010–T014 all [P] (distinct files); US1 entity T015 [P] with the tests
- US3: T026 (unit test) and T027 (entity) in parallel; T027 also parallel with US1/US2 work
- Cross-story: US1, US2, US3 can be staffed in parallel after Foundational (coordinate shared
  `transactions.rb` edits — see note below)

**Shared-file note**: T016–T020 (US1), T023–T024 (US2), and T028–T029 (US3) all edit
`lib/bml_tokenization/transactions.rb`. When staffed in parallel, treat this file as a coordination
point (not marked [P] across stories).

---

## Parallel Example: User Story 1

```bash
# Launch all US1 tests together (distinct files, write-first):
Task: "Public-API contract test for create in spec/contract/transactions_api_spec.rb"
Task: "Remote HTTP contract test for create in spec/contract/transactions_remote_spec.rb"
Task: "Unit tests for create validation/idempotency in spec/unit/transactions_spec.rb"
Task: "Unit tests for the Transaction entity in spec/unit/transaction_spec.rb"
Task: "Sandbox integration test for create in spec/integration/transactions_sandbox_spec.rb"

# Then the entity in parallel with finishing the tests:
Task: "Implement the Transaction value object in lib/bml_tokenization/transaction.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: User Story 1 (create — both paths, idempotency + conflict)
4. **STOP and VALIDATE**: Test create independently against sandbox
5. Deploy/demo if ready

> Note: US1 and US2 are both **P1**. US1 (create) is the minimum shippable slice, but a meaningful P1
> release pairs it with US2 (retrieve) so integrators can confirm payment outcomes. US3 (list, P2)
> follows for reconciliation.

### Incremental Delivery

1. Setup + Foundational → foundation ready
2. US1 (create) → test independently → demo (MVP)
3. US2 (retrieve) → test independently → demo (complete P1)
4. US3 (list) → test independently → demo
5. Polish → leakage inspection, quickstart V1–V27, docs, lint

---

## Notes

- [P] = different files, no dependencies on incomplete tasks
- [Story] label maps each task to its user story for traceability
- Verify every test fails before implementing (Red-Green-Refactor, Constitution II)
- Never accept/return/log a full PAN or CVV; a saved card is referenced only by its safe reference
  (FR-010)
- Commit after each task or logical group; stop at any checkpoint to validate a story independently
