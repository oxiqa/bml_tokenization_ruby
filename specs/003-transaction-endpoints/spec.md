# Feature Specification: Transaction Endpoints

**Feature Branch**: `003-transaction-endpoints`

**Created**: 2026-08-17

**Status**: Draft

**Input**: User description: "add a clss to provide transaction endpoints"

## Clarifications

### Session 2026-08-17

- Q: How does a customer complete payment for a transaction — hosted redirect URL, server-side charge against a stored card-on-file reference, or both? → A: Both — when no stored card is supplied, create returns a hosted payment URL for the customer to complete in the browser; when a card-on-file safe reference is supplied, the transaction is charged server-side without a redirect.
- Q: For the hosted-redirect (new-card) flow, is a customer association required, optional, or disallowed? → A: Always required — every transaction (both the redirect flow and the stored-card charge flow) MUST reference an existing customer; guest/anonymous payments are not supported.
- Q: How is the transaction amount expressed to the library? → A: A positive integer in the currency's smallest (minor) unit — e.g. 15000 means MVR 150.00; decimals/major-unit values are not accepted.
- Q: How should the library handle a create call whose integrator reference was already used? → A: Idempotent — the library returns the existing transaction for a repeated integrator reference and does not create a second charge; the integrator reference is the idempotency key.
- Q: What should the list operation support? → A: Paginated listing with optional filters by customer and by status (e.g. pending, succeeded, failed/cancelled); both filters are optional and may be combined.

### Session 2026-08-27

- Q: How should the transaction list operation paginate, and what page-size limits apply? → A: Match the customer resource — page-number pagination exposing a page number and a page size, default 20 records per page, maximum 100; a requested page size above 100 is rejected with a clear error.
- Q: How should the library validate the currency before calling the platform? → A: MVR only — the library accepts only MVR and rejects any other currency with a validation error locally, before any remote call.
- Q: What is the canonical set of transaction statuses the library exposes and allows as list filters? → A: Four distinct statuses — pending, succeeded, failed, and cancelled — where cancelled (customer-abandoned) is distinguishable from failed (declined/errored).
- Q: When a create call reuses an integrator reference with different payment details, how should the library respond? → A: Reject as a conflict — an identical repeat returns the original transaction, but if a reused reference carries different material parameters (amount, currency, customer, or card) the library fails with a conflict error naming the mismatch.
- Q: Is the customer return/redirect URL a required input, and does it apply to both create flows? → A: Required for the new-card hosted-redirect flow only (create rejects locally if missing); not required and ignored for the stored-card server-side charge flow.
- Q: Is the integrator reference unique across all transactions, or only within a single customer? → A: Global — the reference must be unique across all transactions; reusing it triggers the idempotent return (or conflict) regardless of which customer is supplied.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create a transaction (Priority: P1)

An integrator using the tokenization library wants to initiate a payment on the Bank of Maldives
platform so a customer can pay for goods or services. Working through the existing configured
client, they supply the payment details (the paying customer, an amount in minor units, a currency,
an integrator-side reference, and where to return the customer afterward) and receive back a
transaction record that includes the platform-assigned transaction identifier and the information
needed to direct the customer to complete payment. If they instead supply one of the customer's
stored cards (by safe reference), the payment is charged directly and the record reflects the
outcome without a redirect.

**Why this priority**: Creating a transaction is the reason this resource exists; every other
operation (retrieve, list, verify outcome) depends on a transaction first being created. This is
the minimum viable slice that delivers value on its own.

**Independent Test**: Can be fully tested by calling the create operation with valid payment
details against the sandbox environment and confirming a transaction record with an identifier and
a completion reference is returned. Delivers value because integrators can immediately start a
payment.

**Acceptance Scenarios**:

1. **Given** a configured client and valid payment details (an existing customer, an amount in minor
   units, a currency, and an integrator reference) with no stored card supplied, **When** the
   integrator creates a transaction, **Then** a transaction record containing a platform-assigned
   identifier, the submitted details, a pending status, and a hosted payment URL to direct the
   customer to complete payment is returned.
2. **Given** an existing customer and one of that customer's stored cards (by safe reference), **When**
   the integrator creates a transaction charging that card, **Then** the transaction is charged
   server-side without a redirect and the returned record reflects the resulting status (succeeded or
   failed) directly.
3. **Given** payment details that are missing a required field or contain an invalid amount (e.g.
   zero, negative, or non-integer), **When** the integrator attempts to create a transaction, **Then**
   the operation fails with an error that names the invalid or missing field, and no transaction is
   created and no remote call is made.
4. **Given** a client configured for sandbox mode, **When** a transaction is created, **Then** the
   transaction is created in the sandbox environment and is not visible in production.

---

### User Story 2 - Retrieve a transaction by identifier (Priority: P1)

An integrator has a transaction identifier and needs to look up the current state of that
transaction — most importantly its status — to determine whether the payment succeeded, failed, or
is still pending (for order fulfilment, reconciliation, or display).

**Why this priority**: Retrieval is how an integrator learns the outcome of a payment; without it a
created transaction has no confirmable result. It is core to almost every downstream flow and is
independently valuable.

**Independent Test**: Can be tested by creating a transaction, then retrieving it by its identifier
and confirming the returned status and details match. Delivers value as a standalone status/lookup
capability.

**Acceptance Scenarios**:

1. **Given** an existing transaction identifier, **When** the integrator retrieves the transaction,
   **Then** the current transaction record, including its status, is returned.
2. **Given** an identifier that does not correspond to any transaction, **When** the integrator
   retrieves the transaction, **Then** a not-found error is returned.

---

### User Story 3 - List transactions (Priority: P2)

An integrator wants to browse or reconcile the transactions on the platform, retrieving them in
pages so that large result sets remain manageable, and optionally narrowing the results to a single
customer or to a particular status (for example, all pending payments awaiting completion).

**Why this priority**: Listing supports reconciliation and administrative views but is not required
to create or confirm an individual payment, so it ranks below create and retrieve.

**Independent Test**: Can be tested by creating one or more transactions and confirming they appear
in a listed page of results, and that filtering by customer or status returns only the matching
transactions. Delivers value as a browse/reconcile capability.

**Acceptance Scenarios**:

1. **Given** one or more existing transactions, **When** the integrator lists transactions, **Then**
   a page of transaction records is returned.
2. **Given** more transactions exist than fit in a single page, **When** the integrator requests a
   specific page, **Then** only that page of results is returned.
3. **Given** transactions belonging to different customers, **When** the integrator lists
   transactions filtered by a customer identifier, **Then** only that customer's transactions are
   returned.
4. **Given** transactions in different statuses, **When** the integrator lists transactions filtered
   by a status, **Then** only transactions in that status are returned; an unrecognized status value
   returns a validation error.
5. **Given** no transactions exist (or none match the applied filters), **When** the integrator
   lists transactions, **Then** an empty page is returned rather than an error.

---

### Edge Cases

- What happens when a transaction is created for a customer that does not exist? The operation MUST
  fail with an error identifying the missing customer and MUST NOT create a transaction (see
  FR-005a).
- What happens when the client is misconfigured (missing or invalid credentials)? The operation
  MUST fail with an authentication/configuration error rather than silently returning an empty
  result.
- How does the system handle a remote platform outage or timeout? The operation MUST surface a
  clear, actionable error to the caller rather than hanging indefinitely or returning a partial
  record.
- What happens when a transaction is created with a currency other than MVR, or a malformed
  currency? The operation MUST fail locally with an error naming the currency field and MUST NOT
  create a transaction or make a remote call (see FR-005c).
- What happens when a new-card (hosted-redirect) transaction is created without a return/redirect
  URL? The operation MUST fail locally with an error naming the return URL and MUST NOT make a
  remote call; the return URL is not required for the stored-card charge flow (see FR-002).
- What happens when the amount is zero, negative, non-integer (a decimal/fractional minor unit), or
  below/above the platform's accepted limits? The operation MUST fail with a validation error
  identifying the amount, and MUST NOT create a transaction (see FR-005b).
- What happens when a transaction is retrieved while payment is still in progress? Its status MUST
  reflect a pending/unresolved state, distinguishable from a succeeded or failed outcome.
- What happens when a duplicate integrator reference is submitted? If the request parameters are
  identical, the operation MUST be idempotent: it returns the existing transaction for that
  reference and does not create a second transaction or initiate a second charge. If the reused
  reference carries different material parameters (amount, currency, customer, or card), the
  operation MUST fail with a conflict error naming the mismatch and MUST NOT create a transaction or
  charge (see FR-013). Reference uniqueness is global, so a reference reused under a different
  customer is treated the same way.
- What happens when a page number beyond the available results is requested? An empty page MUST be
  returned.
- What happens when a page size above the maximum (100) is requested? The library MUST reject the
  request with a clear error naming the page size (see FR-004).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The library MUST expose transaction operations as a dedicated transaction resource
  reachable through the existing configured client, consistent with how other resources (e.g.
  customers, cards on file) are exposed.
- **FR-002**: The library MUST allow an integrator to create a transaction by supplying the payment
  details (at minimum an amount, a currency, an integrator-side reference, and the identifier of an
  existing customer) and MUST return the
  resulting transaction record including its platform-assigned identifier and its status. The
  library MUST support two completion paths: (a) when no stored card is supplied, the returned
  record MUST include a hosted payment URL the customer is directed to in order to complete payment,
  and the transaction's initial status MUST be pending; (b) when a card-on-file safe reference is
  supplied, the transaction MUST be charged server-side without a hosted redirect, and the returned
  record MUST reflect the resulting status (succeeded or failed) directly. A customer return/redirect
  URL MUST be supplied for the hosted-redirect flow (path a) and the library MUST reject a create
  call locally, without a remote call, if it is missing; the return URL is not required for the
  stored-card charge flow (path b) and is ignored there.
- **FR-003**: The library MUST allow an integrator to retrieve a single transaction by its
  identifier, returning its current status and details.
- **FR-004**: The library MUST allow an integrator to list transactions using page-number
  pagination, exposing both a page number and a page size. When page size is not supplied it MUST
  default to 20 records per page, and the library MUST NOT permit a page size greater than 100
  (a requested page size above 100 MUST be rejected with a clear error). The list MUST support
  optional filtering by customer and by status (one of `pending`, `succeeded`, `failed`, or
  `cancelled`); the filters MUST be optional and combinable. An invalid filter value (e.g. an
  unrecognized status) MUST fail with a validation error identifying the offending filter.
- **FR-005**: The library MUST validate that required transaction inputs are present and
  well-formed (including a supported currency per FR-005c and an existing-customer identifier)
  before contacting the remote platform, returning a clear error identifying any missing or invalid
  field without making a remote call.
- **FR-005a**: Every transaction MUST reference an existing customer; the library MUST NOT create a
  guest/anonymous transaction. Creating a transaction for a customer identifier that does not exist
  MUST fail with an error identifying the missing customer, and no transaction MUST be created.
- **FR-005b**: The amount MUST be expressed as a positive integer in the currency's smallest (minor)
  unit; the library MUST reject non-integer, zero, or negative amounts with a validation error
  naming the amount field, without making a remote call.
- **FR-005c**: The library MUST accept only MVR as the transaction currency; any other currency
  value MUST be rejected locally with a validation error naming the currency field, before any
  remote call is made.
- **FR-006**: The library MUST expose the transaction's status using four distinct canonical
  values — `pending` (in progress/unresolved), `succeeded`, `failed` (declined or errored), and
  `cancelled` (customer-abandoned) — such that a cancelled payment is distinguishable from a failed
  one.
- **FR-007**: The library MUST perform every transaction operation against the environment (sandbox
  or production) selected on the client, and MUST NOT cross environments.
- **FR-008**: The library MUST authenticate transaction requests using the credentials configured
  on the client, without requiring the integrator to supply credentials per call.
- **FR-009**: The library MUST surface remote platform errors (validation, not-found, conflict,
  authentication, and availability errors) to the caller with actionable context, distinguishable
  by error condition.
- **FR-010**: The library MUST NOT accept, return, log, or persist a full payment card number or
  card security code as part of any transaction operation; where a saved payment instrument is
  used, it MUST be referenced only by a safe reference (as produced by the card-on-file resource),
  consistent with the project constitution's data-protection principle.
- **FR-011**: Every transaction operation MUST be independently testable against the sandbox
  environment without requiring production credentials.
- **FR-012**: Every transaction create and retrieve operation MUST be recorded in the audit trail
  (who, what, when, and outcome) sufficient to reconstruct access, without including any sensitive
  authentication data or full card number, per the constitution's auditability principle.
- **FR-013**: Creating a transaction MUST be idempotent on the integrator-supplied reference, which
  is the idempotency key and MUST be unique across all transactions (a global namespace, not scoped
  per customer). If a transaction with the same reference already exists and the new request's
  material parameters (amount, currency, customer, and card, if any) are identical, the library MUST
  return that existing transaction and MUST NOT create a second transaction or initiate a second
  charge. If the same reference is reused with any differing material parameter, the library MUST
  fail with a conflict error identifying the mismatch and MUST NOT create a transaction or initiate
  a charge.

### Key Entities *(include if feature involves data)*

- **Transaction**: Represents a single payment initiated on the Bank of Maldives platform. Key
  attributes include a platform-assigned unique identifier, an amount (a positive integer in the
  currency's minor unit) and currency (MVR only), an integrator-supplied reference for correlation,
  a status reflecting the payment lifecycle — one of four distinct values `pending`, `succeeded`,
  `failed`, or `cancelled` — a required association to an existing customer, and —
  depending on the completion path — either a hosted payment URL (for the redirect flow when no
  stored card is supplied) or an association to a card on file by safe reference (for the
  server-side charge flow). The transaction never exposes a full card number or security code.
- **Transaction List Page**: Represents a bounded subset of transaction records returned for a
  single list request, along with the information needed to request subsequent pages. It is
  addressed by a page number and a page size (default 20, maximum 100 records per page).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An integrator can create a transaction and receive a valid transaction identifier and
  a means to complete payment on the first attempt using only the documented required fields, with
  no undocumented steps.
- **SC-002**: 100% of the three transaction operations (create, retrieve, list) are demonstrable
  end-to-end against the sandbox environment.
- **SC-003**: Every invalid-input scenario returns an error that names the specific offending field,
  verified for 100% of required fields (including amount and currency).
- **SC-004**: The status of any transaction can be determined by retrieval such that the four
  outcomes pending, succeeded, failed, and cancelled are unambiguously distinguishable in 100% of
  cases.
- **SC-005**: No transaction operation exposes a full card number or card security code in any
  input, returned record, error, or log (verified by inspection across all operations).
- **SC-006**: A transaction created in sandbox is never visible in production and vice versa,
  confirmed by environment isolation testing.
- **SC-007**: Re-submitting create with an already-used integrator reference and identical
  parameters results in 0 duplicate transactions and 0 additional charges in 100% of cases; the
  original transaction is returned. Re-submitting the same reference with any differing material
  parameter returns a conflict error and creates 0 transactions and 0 charges in 100% of cases.

## Assumptions

- `bml_tokenization` is a client-side integration library that wraps the Bank of Maldives
  tokenization / Connect API, following the same structure as the existing customer and card-on-file
  resources where a configured client object exposes per-resource classes. The transaction
  capability is exposed the same way.
- Transaction operations reuse the existing client for base URL, environment mode
  (sandbox/production), and authentication credentials (API key / app id); this feature does not
  introduce a new configuration or authentication mechanism.
- Operations in scope for this feature are: create a transaction, retrieve a transaction by
  identifier, and list transactions (paginated, with optional customer and status filters).
  Refunding, voiding/cancelling, or capturing a
  previously authorized transaction are out of scope unless later confirmed to be supported by the
  remote platform and required.
- The remote platform is the source of truth for transaction records and for the exact set of
  transaction fields, their required/optional status, amount limits, and
  uniqueness rules; the library mirrors that contract rather than defining its own. Currency is the
  one exception: the library constrains it to MVR and rejects any other currency locally before a
  remote call (see FR-005c), rather than deferring the supported-currency set to the platform.
  Duplicate
  handling is normalized by the library to an idempotent outcome on the integrator reference:
  an identical repeat returns the existing transaction, while a reused reference with differing
  material parameters yields a conflict error — regardless of the platform's raw response. The
  reference is a global idempotency key (unique across all transactions, not per customer).
- The actual payment authorization and settlement are performed by the remote platform; this
  library initiates and observes transactions but does not itself move funds or process card data.
- Where a payment reuses a stored card, the card is referenced by the safe reference produced by
  the card-on-file resource (feature `002-card-on-file-endpoints`); this library never receives raw
  card data, consistent with the project constitution (Principle I).
- Handling asynchronous completion notifications (webhooks/callbacks) from the platform is out of
  scope for this feature; integrators determine outcome by retrieving the transaction. A
  redirect/return URL for the customer's browser flow is treated as an input to create, not as a
  callback-handling capability of this library.
- Standard integration-library error handling applies: remote failures are surfaced as errors with
  actionable context rather than swallowed.

## Dependencies

- Requires a configured client (base URL, environment mode, and valid credentials) as already
  established for other resources in the library.
- Requires the customer resource (feature `001-customer-api-endpoints`): every transaction MUST
  reference an existing customer, so a customer must be created before a transaction can be
  initiated. Optionally references the card-on-file resource (feature
  `002-card-on-file-endpoints`) when a transaction charges a stored card by safe reference.
- Requires access to the Bank of Maldives sandbox environment for independent testing of each
  operation.
