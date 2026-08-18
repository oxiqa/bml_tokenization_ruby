# Feature Specification: Tokenization Endpoints

**Feature Branch**: `004-tokenization-endpoints`

**Created**: 2026-08-17

**Status**: Draft

**Input**: User description: "add a class to add tokenization endpoints"

## Clarifications

### Session 2026-08-17

- Q: Should the library expose detokenization (returning the full card number for a token), or keep it permanently out of scope with only masked data returned? → A: Out of scope — the library exposes no operation that returns the full card number; only masked summaries are ever returned. Downstream systems use the token; the platform resolves it internally.
- Q: Within what boundary is "the same card" scoped for the tokenize idempotency rule? → A: Per merchant/app account and environment — a card maps to one token within the configured account and environment (sandbox/production); a different account or environment yields a different token.
- Q: When a token is revoked, what happens to card-on-file records or other resources that still reference it? → A: Reject on use, no cascade — revocation permanently invalidates the token so any later use (charging a card-on-file entry or creating a transaction) is rejected; the library does not auto-delete or mutate the referencing records.
- Q: What card input does the tokenize operation accept? → A: Single-use handle only — the sole accepted input is a single-use card handle from a hosted capture step; the library never accepts a raw card number or security code, keeping it out of full cardholder-data (PCI) scope.
- Q: What identifies the "who" in the audit record for tokenization operations? → A: Account identity by default, plus an optional integrator-supplied actor reference — the audit "who" is the configured account/app identity, and each operation MAY accept an optional actor (operator/user) reference to enrich the record; no per-call actor is required.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Tokenize a captured card (Priority: P1)

An integrator wants to convert a customer's payment card into a durable, non-reversible token so
the card can be referenced in later operations (payments, card-on-file) without the integrator ever
handling the raw card number. Working through the existing configured client, they submit a
single-use card handle produced by a hosted capture step and receive back a token record containing
a safe token reference and a masked summary of the card — never the full card number or security
code.

**Why this priority**: Tokenizing a card is the reason this resource exists; every other operation
(retrieve, revoke) and every downstream consumer (transactions, card-on-file) depends on a token
first being issued. This is the minimum viable slice that delivers value on its own.

**Independent Test**: Can be fully tested by tokenizing a valid single-use card handle against the
sandbox environment and confirming a token record with a safe reference and masked summary is
returned, and that no full card number or security code appears anywhere in the response. Delivers
value because integrators can immediately obtain a reusable token.

**Acceptance Scenarios**:

1. **Given** a configured client and a valid single-use card handle, **When** the integrator
   tokenizes the card, **Then** a token record containing a safe token reference and a masked card
   summary (e.g. scheme, last four digits, expiry) is returned, and no full card number or security
   code is present.
2. **Given** a card handle that is invalid, already consumed, or expired, **When** the integrator
   attempts to tokenize it, **Then** the operation fails with an error identifying the problem and no
   token is issued.
3. **Given** a client configured for sandbox mode, **When** a card is tokenized, **Then** the token
   is issued in the sandbox environment and is not valid or visible in production.

---

### User Story 2 - Retrieve token details (Priority: P1)

An integrator has a token reference and needs to look up the current, non-sensitive details of the
token (such as its masked summary, card scheme, expiry, and validity status) in order to display it
or decide whether it can still be used.

**Why this priority**: Retrieval lets an integrator confirm a token exists and read its current
state before using it; it is core to almost every downstream flow and is independently valuable.

**Independent Test**: Can be tested by tokenizing a card, then retrieving the token by its reference
and confirming the returned masked summary matches and no sensitive data is present. Delivers value
as a standalone lookup capability.

**Acceptance Scenarios**:

1. **Given** an existing token reference, **When** the integrator retrieves the token, **Then** the
   current token record is returned with masked summary and validity status only, and no full card
   number or security code.
2. **Given** a token reference that does not correspond to any token, **When** the integrator
   retrieves it, **Then** a not-found error is returned.

---

### User Story 3 - Revoke a token (Priority: P2)

An integrator needs to permanently invalidate a token (at the customer's request, on suspected
compromise, or when the card is no longer valid) so it can no longer be used for any future
operation.

**Why this priority**: Revocation is required for customer control, security response, and
data-minimisation obligations, but it is not part of the initial issue/use loop, so it ranks below
tokenize and retrieve.

**Independent Test**: Can be tested by tokenizing a card, revoking the token, and confirming it can
no longer be retrieved as active and can no longer be used in a downstream operation. Delivers value
as a security-control capability.

**Acceptance Scenarios**:

1. **Given** an active token, **When** the integrator revokes it, **Then** the token is permanently
   invalidated and any subsequent attempt to use it for a payment or other operation is rejected.
2. **Given** a token reference that has already been revoked or never existed, **When** the
   integrator attempts to revoke it, **Then** a not-found (or already-revoked) error is returned and
   no other token is affected.
3. **Given** a token that is still referenced by a card-on-file record, **When** the integrator
   revokes the token, **Then** revocation succeeds without deleting or altering that card-on-file
   record, and any subsequent attempt to charge using the record is rejected because the token is
   revoked.

---

### Edge Cases

- What happens when the client is misconfigured (missing or invalid credentials)? The operation
  MUST fail with an authentication/configuration error rather than silently returning an empty
  result.
- How does the system handle a remote platform outage or timeout during tokenization? The operation
  MUST surface a clear, actionable error rather than hanging or returning a partial record, and MUST
  NOT leave the raw card data anywhere in this library.
- What happens when the same card handle is submitted for tokenization more than once? The operation
  MUST be idempotent for the same underlying card within the same account and environment: it
  returns the existing token rather than issuing a second, distinct token (see FR-011).
- What happens when a revoked or expired token is used in a downstream operation? The operation that
  consumes the token MUST reject it based on its validity status.
- What happens if a caller attempts to obtain the full card number from a token through this
  library? The library MUST provide no operation that returns the full card number; only masked
  representations are ever exposed (see FR-003, and Assumptions on detokenization scope).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The library MUST expose tokenization operations as a dedicated resource reachable
  through the existing configured client, consistent with how other resources (e.g. customers, cards
  on file, transactions) are exposed.
- **FR-002**: The library MUST allow an integrator to tokenize a payment card by supplying a
  pre-tokenized / single-use card handle produced by a hosted capture step, and MUST return a token
  record identified by a safe token reference. The library MUST NOT accept a raw card number or card
  security code as input.
- **FR-003**: The library MUST represent every token only by a safe token reference and a masked
  summary (such as card scheme, last four digits, and expiry), and MUST NEVER return, log, or
  persist the full card number or the card security code.
- **FR-004**: The library MUST allow an integrator to retrieve a single token by its safe reference,
  returning its masked summary and validity status.
- **FR-005**: The library MUST allow an integrator to revoke a token so that it can no longer be
  used in any operation. Revocation MUST be permanent; a revoked token MUST NOT be usable or
  reactivated.
- **FR-005a**: Revoking a token MUST NOT cascade into, delete, or otherwise mutate other resources
  that reference it (such as card-on-file records or transactions); those references remain but any
  attempt to use the revoked token in a downstream operation MUST be rejected based on its revoked
  status.
- **FR-006**: The token value MUST be non-sequential, MUST carry no exploitable relationship to the
  underlying card number, and MUST NOT be reversible to the card number without access to the
  protected token vault (which is not exposed by this library), per the constitution's data
  protection principle.
- **FR-006a**: The library MUST NOT provide any operation that returns, reconstructs, or otherwise
  reveals the full card number for a token (no detokenization). Every card representation the library
  returns MUST be masked.
- **FR-007**: The library MUST validate that required inputs are present and well-formed before
  contacting the remote platform, returning a clear error identifying any missing or invalid input
  without making a remote call.
- **FR-008**: The library MUST perform every tokenization operation against the environment (sandbox
  or production) selected on the client, and MUST NOT cross environments; a token issued in one
  environment MUST NOT be valid in the other.
- **FR-009**: The library MUST authenticate tokenization requests using the credentials configured
  on the client, without requiring the integrator to supply credentials per call.
- **FR-010**: The library MUST surface remote platform errors (validation, not-found, conflict,
  authentication, and availability errors) to the caller with actionable context, distinguishable by
  error condition.
- **FR-011**: Tokenizing a card that has already been tokenized MUST be idempotent within the
  configured merchant/app account and environment: the library MUST return the existing token for
  the same underlying card within that account and environment, and MUST NOT issue a duplicate,
  distinct token for it. A different account or a different environment (sandbox/production) MUST
  yield a distinct token; tokens MUST NOT be shared or correlated across accounts.
- **FR-012**: Every tokenize, retrieve, and revoke operation MUST produce an audit record capturing
  who performed it, which token reference was affected, when, and the outcome — sufficient to
  reconstruct access — and the audit record MUST NOT contain the full card number, the card security
  code, or any sensitive authentication data, per the constitution's auditability principle.
- **FR-012a**: The audit record's actor ("who") MUST default to the configured account/app identity.
  Each operation MUST additionally accept an optional integrator-supplied actor reference (e.g. an
  operator or end-user identifier); when supplied it MUST be recorded in the audit record alongside
  the account identity. A per-call actor MUST NOT be required, and the optional actor reference MUST
  NOT contain sensitive authentication data or cardholder data.
- **FR-013**: The library MUST NOT persist Sensitive Authentication Data (full card number, security
  code, or equivalent) at any point during tokenization, in any store, log, cache, or backup.
- **FR-014**: Every tokenization operation MUST be independently testable against the sandbox
  environment without requiring production credentials.

### Key Entities *(include if feature involves data)*

- **Token**: Represents a non-reversible stand-in for a payment card, issued by the tokenization
  platform. Exposed attributes include a platform-assigned safe token reference, a masked summary
  (card scheme, last four digits, expiry month/year), and a validity status (active / revoked /
  expired). The full card number and security code are never exposed by this entity — only the
  masked representation. The token reference is what downstream resources (transactions, cards on
  file) use to refer to the card.
- **Card Handle (input only)**: A single-use handle produced by a hosted capture step (hosted
  fields / SDK) that stands in for freshly captured card data. It is the only card input this
  library accepts for tokenization; it is never persisted by this library and is consumed by the
  tokenize operation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An integrator can tokenize a valid card handle and receive a safe token reference on
  the first attempt using only the documented required inputs, with no undocumented steps.
- **SC-002**: 100% of tokenization responses, logs, and stored records contain no full card number
  and no card security code (verified by inspection across all operations).
- **SC-003**: All three tokenization operations (tokenize, retrieve, revoke) are demonstrable
  end-to-end against the sandbox environment.
- **SC-004**: After a token is revoked, 100% of subsequent attempts to use it in a downstream
  operation are rejected, and retrieval reports it as not active.
- **SC-005**: A token issued in sandbox is never valid or visible in production and vice versa,
  confirmed by environment isolation testing.
- **SC-006**: Tokenizing the same card twice within the same account and environment yields the same
  token in 100% of cases (no duplicate distinct tokens for one card); the same card under a
  different account or environment yields a distinct token, confirmed by isolation testing.
- **SC-007**: No token value is sequential or derivable from the card number, verified by inspection
  of issued tokens.
- **SC-008**: Every invalid-input scenario returns an error that names the specific problem, verified
  for 100% of required inputs.

## Assumptions

- `bml_tokenization` is a client-side integration library that wraps the Bank of Maldives
  tokenization / Connect API, following the same structure as the existing customer, card-on-file,
  and transaction resources where a configured client object exposes per-resource classes. The
  tokenization capability is exposed the same way.
- Tokenization operations reuse the existing client for base URL, environment mode
  (sandbox/production), and authentication credentials (API key / app id); this feature does not
  introduce a new configuration or authentication mechanism.
- The remote platform performs the actual capture, tokenization, and secure storage of card data;
  this library never receives, stores, or transmits raw card data itself. Card capture happens in a
  hosted step (hosted fields / SDK) that yields a single-use card handle, which is the only card
  input this library accepts for tokenization, consistent with the project constitution's
  data-protection principle (Principle I).
- Operations in scope for this feature are: tokenize a card (issue a token), retrieve a token by
  reference, and revoke a token. Listing tokens is out of scope (enumeration of a customer's saved
  cards is handled by the card-on-file resource, feature `002-card-on-file-endpoints`).
- **Detokenization (returning the full card number for a token) is confirmed out of scope for this
  client library** (see Clarifications and FR-006a). The constitution treats detokenization as a
  specially authorized, audited system capability; this integration library exposes no operation
  that reveals the full card number. Only masked representations are ever returned.
- Tokenization is the lower-level primitive that produces the token reference used by the
  card-on-file resource (to associate a token with a customer for reuse) and by the transaction
  resource (to charge a stored/tokenized card). This feature issues and manages tokens themselves;
  customer association and payment are handled by those other resources.
- The remote platform defines the exact card fields and their required/optional status; the library
  mirrors that contract rather than defining its own. Duplicate handling is normalized by the
  library to an idempotent outcome (return the existing token) regardless of the platform's raw
  response.
- Standard integration-library error handling applies: remote failures are surfaced as errors with
  actionable context rather than swallowed.

## Dependencies

- Requires a configured client (base URL, environment mode, and valid credentials) as already
  established for other resources in the library.
- Requires a hosted capture step (hosted fields / SDK) that produces the single-use card handle this
  library accepts as tokenization input; providing that capture UI is outside this library's scope.
- Requires access to the Bank of Maldives sandbox environment for independent testing of each
  operation.
- Consumed by the card-on-file resource (feature `002-card-on-file-endpoints`) and the transaction
  resource (feature `003-transaction-endpoints`), which reference tokens by their safe reference.
