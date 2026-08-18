# Feature Specification: Card-on-File Endpoints

**Feature Branch**: `002-card-on-file-endpoints`

**Created**: 2026-08-17

**Status**: Draft

**Input**: User description: "add a class to provide card on file endpoints"

## Clarifications

### Session 2026-08-17

- Q: How does a cardholder's card data reach the platform when storing a card on file? → A: The library accepts a pre-tokenized / single-use card handle produced by a hosted capture step (hosted fields / SDK); the raw card number and security code never transit this library.
- Q: When storing a card the customer already has on file, how should the operation behave? → A: Idempotent — return the existing card-on-file record and do not create a duplicate.
- Q: When a card on file is removed, should it be permanently deleted or just deactivated? → A: Permanently deleted — the card-on-file record is fully erased; only the removal event is retained in the audit trail (no card data).
- Q: Does storing a card require capturing the cardholder's consent to store it for future use? → A: No — capturing and retaining cardholder consent is out of scope for this library and is the integrator's responsibility upstream.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Store a card on file for a customer (Priority: P1)

An integrator wants to save a customer's payment card securely so it can be reused for future
payments without asking the cardholder to re-enter details. Working through the existing client,
they associate a card with a customer and receive back a stored card-on-file record that
identifies the saved card by a safe reference and a masked summary — never the full card number.

**Why this priority**: Storing a card is the reason card-on-file exists; every other operation
(list, retrieve, remove, reuse) depends on a card first being on file. This is the minimum viable
slice that delivers value on its own.

**Independent Test**: Can be tested by storing a card for a known customer against the sandbox
environment and confirming a card-on-file record is returned with a safe reference and masked
summary, and that no full card number is present in the response. Delivers value because
integrators can immediately save cards for reuse.

**Acceptance Scenarios**:

1. **Given** a configured client, an existing customer, and a valid single-use card handle, **When**
   the integrator stores the card for that customer, **Then** a card-on-file record is returned
   containing a safe reference and a masked card summary (e.g. last four digits and card scheme),
   and no full card number.
2. **Given** a card handle that is invalid, already consumed, or expired, **When** the integrator
   attempts to store the card, **Then** the operation fails with an error identifying the problem
   and no card is stored.
3. **Given** a client configured for sandbox mode, **When** a card is stored, **Then** it is stored
   in the sandbox environment and is not visible in production.

---

### User Story 2 - List a customer's cards on file (Priority: P1)

An integrator wants to show a customer the cards they have saved (for example, at checkout) so the
customer can pick one for a payment. They request the cards on file for a customer and receive the
saved cards, each represented only by a safe reference and masked summary.

**Why this priority**: Reuse at checkout requires the ability to enumerate a customer's saved
cards; this is core to the card-on-file value proposition and is independently useful.

**Independent Test**: Can be tested by storing one or more cards for a customer, listing them, and
confirming each appears with a masked summary and safe reference. Delivers value as a standalone
"wallet view" capability.

**Acceptance Scenarios**:

1. **Given** a customer with one or more stored cards, **When** the integrator lists the customer's
   cards on file, **Then** each stored card is returned with its safe reference and masked summary.
2. **Given** a customer with no stored cards, **When** the integrator lists the customer's cards on
   file, **Then** an empty result is returned rather than an error.

---

### User Story 3 - Retrieve a single card on file (Priority: P2)

An integrator has a card-on-file reference and needs to look up its current details (such as masked
summary, scheme, and expiry status) before using or displaying it.

**Why this priority**: Retrieval supports display and pre-payment validation but is not required to
store or enumerate cards, so it ranks below store and list.

**Independent Test**: Can be tested by storing a card, retrieving it by its reference, and
confirming the returned masked summary matches. Delivers value as a standalone lookup.

**Acceptance Scenarios**:

1. **Given** an existing card-on-file reference, **When** the integrator retrieves it, **Then** the
   current card-on-file record (masked summary only) is returned.
2. **Given** a reference that does not correspond to any stored card, **When** the integrator
   retrieves it, **Then** a not-found error is returned.

---

### User Story 4 - Remove a card on file (Priority: P2)

An integrator needs to delete a saved card at the customer's request or when it is no longer valid,
so it can no longer be used for payments.

**Why this priority**: Removal is required for customer control and data-minimisation obligations
but is not part of the initial save/reuse loop, so it ranks below storing and listing.

**Independent Test**: Can be tested by storing a card, removing it, and confirming it no longer
appears in the customer's list and can no longer be retrieved. Delivers value as a data-control
capability.

**Acceptance Scenarios**:

1. **Given** an existing card on file, **When** the integrator removes it, **Then** the card no
   longer appears in the customer's list and subsequent retrieval returns a not-found error.
2. **Given** a card-on-file reference that has already been removed or never existed, **When** the
   integrator attempts to remove it, **Then** a not-found error is returned and no other card is
   affected.

---

### Edge Cases

- What happens when a card is stored for a customer that does not exist? The operation MUST fail
  with an error identifying the missing customer and MUST NOT store the card.
- What happens when the same card is stored twice for the same customer? The operation MUST be
  idempotent: it returns the existing card-on-file record and does not create a duplicate entry
  (see FR-013).
- How does the system handle a remote platform outage or timeout? The operation MUST surface a
  clear, actionable error rather than hanging or returning a partial record.
- What happens when a card on file has expired? Its expiry status MUST be discoverable, and any
  attempt to use it for payment MUST be rejectable based on that status.
- What happens if the client is misconfigured (missing or invalid credentials)? The operation MUST
  fail with an authentication/configuration error rather than silently returning empty results.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The library MUST expose card-on-file operations as a dedicated resource reachable
  through the existing configured client, consistent with how other resources (e.g. customers,
  transactions) are exposed.
- **FR-002**: The library MUST allow an integrator to store a payment card on file for an existing
  customer by supplying a pre-tokenized / single-use card handle produced by a hosted capture step,
  and MUST return a card-on-file record identified by a safe reference. The library MUST NOT accept
  a raw card number or security code as input for storing a card on file.
- **FR-003**: The library MUST represent every stored card only by a safe reference and a masked
  summary (such as card scheme, last four digits, and expiry), and MUST NEVER return, log, or
  persist the full card number or the card security code.
- **FR-004**: The library MUST allow an integrator to list the cards on file for a given customer.
- **FR-005**: The library MUST allow an integrator to retrieve a single card on file by its safe
  reference.
- **FR-006**: The library MUST allow an integrator to remove a card on file so that it can no
  longer be used for payments. Removal MUST permanently delete the card-on-file record (not merely
  deactivate it); the removed card MUST NOT be retrievable or recoverable afterward.
- **FR-006a**: A removal MUST produce an audit record capturing who removed which card reference
  and when, per the constitution's auditability principle; the audit record MUST NOT contain card
  data (no full number, no masked summary beyond the safe reference).
- **FR-007**: The library MUST validate that required inputs (customer association and card
  details) are present and well-formed before contacting the remote platform, returning a clear
  error identifying any missing or invalid input without making a remote call.
- **FR-008**: The library MUST perform every card-on-file operation against the environment
  (sandbox or production) selected on the client, and MUST NOT cross environments.
- **FR-009**: The library MUST authenticate card-on-file requests using the credentials configured
  on the client, without requiring the integrator to supply credentials per call.
- **FR-010**: The library MUST surface remote platform errors (validation, not-found, conflict,
  authentication, and availability errors) to the caller with actionable context, distinguishable
  by error condition.
- **FR-011**: Each card on file MUST be associable with the customer that owns it, so that cards
  can be listed and controlled per customer.
- **FR-012**: Every card-on-file operation MUST be independently testable against the sandbox
  environment without requiring production credentials.
- **FR-013**: Storing a card that the customer already has on file MUST be idempotent: the library
  MUST return the existing card-on-file record and MUST NOT create a duplicate entry for the same
  underlying card.

### Key Entities *(include if feature involves data)*

- **Card on File**: Represents a customer's payment card saved for reuse. Exposed attributes
  include a platform-assigned safe reference, a masked summary (card scheme, last four digits,
  expiry month/year), an expiry/validity status, and the owning customer. The full card number and
  security code are never exposed by this entity — only the tokenized/masked representation.
- **Card Owner (Customer)**: The customer entity to which a card on file belongs; a customer may
  have zero or more cards on file. (Defined by the customer feature; referenced here.)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An integrator can store a card for an existing customer and receive a safe reference
  on the first attempt using only the documented required inputs, with no undocumented steps.
- **SC-002**: 100% of card-on-file responses, logs, and stored records contain no full card number
  and no card security code (verified by inspection across all operations).
- **SC-003**: All four card-on-file operations (store, list, retrieve, remove) are demonstrable
  end-to-end against the sandbox environment.
- **SC-004**: After a card is removed, it appears in 0% of subsequent list results for its customer
  and retrieval returns a not-found error 100% of the time.
- **SC-005**: A card stored in sandbox is never visible in production and vice versa, confirmed by
  environment isolation testing.
- **SC-006**: Every invalid-input scenario returns an error that names the specific problem,
  verified for 100% of required inputs.

## Assumptions

- `bml_tokenization` is a client-side integration library that wraps the Bank of Maldives
  tokenization / Connect API, following the same structure as the existing customer resource where
  a configured client object exposes per-resource classes. The card-on-file capability is exposed
  the same way.
- Card-on-file operations reuse the existing client for base URL, environment mode
  (sandbox/production), and authentication; this feature does not introduce a new configuration or
  authentication mechanism.
- A card on file belongs to a customer created via the customer resource (feature
  `001-customer-api-endpoints`); a customer must exist before a card can be stored for them.
- Operations in scope for this feature are: store a card, list a customer's cards, retrieve a card
  by reference, and remove a card. Updating stored card metadata (e.g. changing the billing
  details on an existing card) and setting a "default" card are out of scope unless later
  confirmed to be supported and required.
- Initiating an actual payment/charge using a stored card is out of scope for this feature; that is
  handled by the transactions resource, which references the card-on-file's safe reference.
- Capturing, presenting, and retaining the cardholder's consent to store a card for future use is
  out of scope for this library; the integrator is responsible for obtaining and recording consent
  (per scheme stored-credential requirements) before invoking the store operation. The library does
  not accept or persist a consent artifact.
- The remote platform is the source of truth for stored cards and performs the actual capture and
  tokenization of card data; the library never receives, stores, or transmits raw card data
  itself. Card capture happens in a hosted step (hosted fields / SDK) that yields a single-use card
  handle, which is the only card input this library accepts, consistent with the project
  constitution's data-protection principle (Principle I).
- The remote platform defines the exact card fields and their required/optional status; the
  library mirrors that contract rather than defining its own. Duplicate handling is normalized by
  the library to an idempotent outcome (return the existing card) regardless of the platform's raw
  response.

## Dependencies

- Requires the customer resource (feature `001-customer-api-endpoints`) so that cards can be
  associated with an existing customer.
- Requires a configured client (base URL, environment mode, and valid credentials) as already
  established for other resources in the library.
- Requires access to the Bank of Maldives sandbox environment for independent testing of each
  operation.
