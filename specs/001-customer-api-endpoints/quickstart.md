# Quickstart & Validation: Customer API Endpoints

**Feature**: `001-customer-api-endpoints` | **Date**: 2026-08-18

A run/validation guide proving the create → retrieve → list → update flow works end-to-end and upholds
the environment-isolation and data-protection guarantees. Implementation details live in `tasks.md`
(Phase 2) and the code; this guide only runs and checks. See [data-model.md](./data-model.md) and
[contracts/](./contracts/) for field- and contract-level detail.

## Prerequisites

- Ruby 3.1+ and Bundler.
- The `bml_tokenization` gem checked out with its shared `Client` available.
- **For deterministic tests**: no credentials needed (HTTP is stubbed with WebMock/fixtures).
- **For the opt-in sandbox suite (FR-011)**: BML **sandbox** credentials (API key / App ID), supplied
  via environment variables — never committed (Constitution Security & Compliance). Example:
  `BML_ENV=sandbox`, `BML_API_KEY=…`, `BML_APP_ID=…`.

## Setup

```bash
bundle install
```

## Run the deterministic suite (no credentials)

```bash
bundle exec rspec spec/contract spec/unit
```

Expected: all contract + unit specs pass, including the checks that assert **no SAD/PAN appears in any
output or log** and that empty/beyond-range list pages return an empty page rather than an error.

## Run the opt-in sandbox integration suite (credential-gated)

```bash
BML_ENV=sandbox BML_API_KEY=... BML_APP_ID=... \
  bundle exec rspec spec/integration/customers_sandbox_spec.rb
```

Expected: skips cleanly if credentials are absent; otherwise exercises the real sandbox end-to-end.

## Validation scenarios (map to spec acceptance criteria)

| # | Scenario | Steps | Expected outcome | Spec ref |
|---|----------|-------|------------------|----------|
| V1 | Create a customer | Call `create(details)` with valid `first_name`, `last_name`, `email` | Returns `Customer` with platform-assigned `id` + submitted details | US1-1, SC-001 |
| V2 | Reject missing required field pre-remote | Call `create` omitting `first_name`, `last_name`, or `email` | Validation error **names** the field; **no** network call; no customer created | US1-2, FR-006, SC-003 |
| V3 | Environment isolation on create | Create in sandbox mode | Customer created in sandbox, not production | US1-3, FR-007, SC-005 |
| V4 | Retrieve a customer | `retrieve(id)` for an existing customer | Current record returned | US2-1 |
| V5 | Retrieve unknown | `retrieve(bogus)` | Not-found error | US2-2 |
| V6 | List customers | Create one+ customers, then `list` | A page of records (default `page_size` 20) is returned | US3-1 |
| V7 | List a specific page | More customers than one page, request `list(page: 2, page_size: n)` | Only that page of results is returned | US3-2 |
| V8 | List when none exist | `list` with no customers | **Empty** page (not an error) | Edge case |
| V9 | List beyond available results | Request a `page` past the results | **Empty** page (not an error) | Edge case |
| V10 | Reject over-cap page size | `list(page_size: 101)` | Validation error **names** `page_size`; **no** network call | FR-004, FR-006 |
| V11 | Update a customer (full replace) | `update(id, full_record)` with valid values, then retrieve | Updated record returned; retrieval reflects it; fields omitted from the record are cleared | US4-1, FR-005 |
| V12 | Update with invalid/missing required value | `update(id, record)` with a bad or missing required field | Validation error **names** the field; customer unchanged; no remote call | US4-2, FR-006 |
| V13 | Duplicate create | Create a customer that violates platform uniqueness | Conflict/duplicate error surfaced to caller | Edge case, FR-009 |
| V14 | Misconfigured client | Call any op with missing/invalid credentials | Auth/config error (not a silent empty result) | Edge case, FR-008 |
| V15 | No SAD/PAN leakage | Perform each op; inspect outputs and logs | No SAD or full card number in any error, log, or record | FR-010, SC-004 |

## Done / acceptance

The feature is validated when V1–V15 pass (deterministic suite green; sandbox suite green where
credentials are provided) and inspection confirms zero SAD/PAN leakage across outputs and logs
(SC-004), all four operations are demonstrable end-to-end against sandbox (SC-002), and environment
isolation holds (SC-005).
