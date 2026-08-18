# Quickstart & Validation: Tokenization Endpoints

**Feature**: `004-tokenization-endpoints` | **Date**: 2026-08-17

A run/validation guide proving the tokenize → retrieve → revoke flow works end-to-end and upholds the
security guarantees. Implementation details live in `tasks.md` (Phase 2) and the code; this guide only
runs and checks. See [data-model.md](./data-model.md) and [contracts/](./contracts/) for field- and
contract-level detail.

## Prerequisites

- Ruby 3.1+ and Bundler.
- The `bml_tokenization` gem checked out with its shared `Client` available.
- **For deterministic tests**: no credentials needed (HTTP is stubbed with WebMock/fixtures).
- **For the opt-in sandbox suite (FR-014)**: BML **sandbox** credentials (API key / App ID) and a
  sandbox-issued single-use card handle, supplied via environment variables — never committed
  (Constitution Security & Compliance). Example: `BML_ENV=sandbox`, `BML_API_KEY=…`, `BML_APP_ID=…`.

## Setup

```bash
bundle install
```

## Run the deterministic suite (no credentials)

```bash
bundle exec rspec spec/contract spec/unit
```

Expected: all contract + unit specs pass, including the masking spec that asserts **no PAN/CVV appears
in any output or log**.

## Run the opt-in sandbox integration suite (credential-gated)

```bash
BML_ENV=sandbox BML_API_KEY=... BML_APP_ID=... \
  bundle exec rspec spec/integration/tokenization_sandbox_spec.rb
```

Expected: skips cleanly if credentials are absent; otherwise exercises the real sandbox end-to-end.

## Validation scenarios (map to spec acceptance criteria)

| # | Scenario | Steps | Expected outcome | Spec ref |
|---|----------|-------|------------------|----------|
| V1 | Tokenize a valid handle | Call `tokenize(handle)` | Returns `Token` (`active`) with masked summary; no full PAN/CVV anywhere | US1-1, SC-001, SC-002 |
| V2 | Reject bad handle | Call `tokenize` with invalid/consumed/expired handle | Fails with error; **no** token issued | US1-2 |
| V3 | Reject raw card / bad input pre-remote | Call `tokenize` with missing handle | Validation error names the field; **no** network call | FR-007 |
| V4 | Idempotent tokenize | Tokenize the same card twice (same account+env) | Same token both times; no duplicate | US-edge, FR-011, SC-006 |
| V5 | Account/env isolation | Tokenize same card under a different env | Distinct token; sandbox token not valid in production | FR-008, SC-005/006 |
| V6 | Retrieve token | `retrieve(reference)` for an issued token | Masked summary + `status`; no full PAN | US2-1 |
| V7 | Retrieve unknown | `retrieve(bogus)` | Not-found error | US2-2 |
| V8 | Revoke token | `revoke(reference)` then attempt to use it downstream | Token `revoked`; later use rejected | US3-1, SC-004 |
| V9 | Revoke does not cascade | Revoke a token referenced by a card-on-file record | Revoke succeeds; the referencing record is **not** deleted/altered; later charge via it is rejected | US3-3, FR-005a |
| V10 | Revoke unknown/already-revoked | `revoke(bogus)` or double-revoke | Not-found/already-revoked error; no other token affected | US3-2 |
| V11 | No detokenization exists | Inspect the public API | There is **no** method that returns a full card number | FR-006a, Clarification Q1 |
| V12 | Audit emitted, no card data | Perform each operation; inspect audit records | One record per op with account [+ optional actor], token ref, outcome; **no** PAN/CVV/handle | FR-012, FR-012a |

## Done / acceptance

The feature is validated when V1–V12 pass (deterministic suite green; sandbox suite green where
credentials are provided) and the masking spec confirms zero PAN/CVV leakage across outputs and logs.
