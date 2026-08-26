# Feature Specification: Customer API Endpoints

**Feature Branch**: `001-customer-api-endpoints`

**Created**: 2026-08-17

**Status**: Draft

**Input**: User description: "create class to handle customer related API endpoints"

## Clarifications

### Session 2026-08-23

- Q: Which customer fields must the library require and validate locally (before any remote call) when creating a customer? → A: Email + full name (first and last name) required locally; phone and integrator reference optional. The remote platform still enforces its own additional rules.
- Q: When updating a customer, should the operation apply a partial update or a full replace? → A: Full replace — the caller must supply the complete customer record on every update; fields omitted from the update are cleared/reset.
- Q: What pagination controls should the list operation expose, and what default and maximum page size should apply? → A: Expose page number and page size; default 20 records per page, maximum 100.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create a customer (Priority: P1)

An integrator using the tokenization library wants to register a customer with the Bank of
Maldives platform so that payment instruments and transactions can later be associated with that
customer. Working through the existing client object, they supply the customer's identifying
details and receive back a persisted customer record, including the platform-assigned customer
identifier.

**Why this priority**: Without the ability to create a customer, no other customer operation is
possible — every retrieve, list, or update depends on a customer existing. This is the minimum
viable slice that delivers value on its own.

**Independent Test**: Can be fully tested by calling the create operation with valid customer
details against the sandbox environment and confirming a customer record with an identifier is
returned. Delivers value because integrators can immediately onboard customers.

**Acceptance Scenarios**:

1. **Given** a configured client and valid customer details, **When** the integrator creates a
   customer, **Then** a customer record containing a platform-assigned identifier and the
   submitted details is returned.
2. **Given** customer details that are missing a required field, **When** the integrator attempts
   to create a customer, **Then** the operation fails with an error that names the invalid or
   missing field, and no customer is created.
3. **Given** a client configured for sandbox mode, **When** a customer is created, **Then** the
   customer is created in the sandbox environment and not in production.

---

### User Story 2 - Retrieve a customer by identifier (Priority: P1)

An integrator has a customer identifier and needs to look up the current details of that customer
(for display, reconciliation, or before initiating a transaction). They request the customer by
identifier and receive the current record.

**Why this priority**: Retrieval is required to confirm a customer exists and to read current
state; it is core to almost every downstream flow and is independently valuable.

**Independent Test**: Can be tested by creating a customer, then retrieving it by its identifier
and confirming the returned details match. Delivers value as a standalone lookup capability.

**Acceptance Scenarios**:

1. **Given** an existing customer identifier, **When** the integrator retrieves the customer,
   **Then** the current customer record is returned.
2. **Given** an identifier that does not correspond to any customer, **When** the integrator
   retrieves the customer, **Then** a not-found error is returned.

---

### User Story 3 - List customers (Priority: P2)

An integrator wants to browse or reconcile the customers registered on the platform, retrieving
them in pages so that large result sets remain manageable.

**Why this priority**: Listing supports reconciliation and administrative views but is not
required to onboard or transact with an individual customer, so it ranks below create/retrieve.

**Independent Test**: Can be tested by creating one or more customers and confirming they appear
in a listed page of results. Delivers value as a browse/reconcile capability.

**Acceptance Scenarios**:

1. **Given** one or more existing customers, **When** the integrator lists customers, **Then** a
   page of customer records is returned.
2. **Given** more customers exist than fit in a single page, **When** the integrator requests a
   specific page, **Then** only that page of results is returned.

---

### User Story 4 - Update a customer (Priority: P3)

An integrator needs to correct or change a customer's mutable details (such as contact
information) after the customer has been created.

**Why this priority**: Updating is a convenience that improves data quality but is not required
for the primary onboarding and transaction flows, so it is the lowest priority in this feature.

**Independent Test**: Can be tested by creating a customer, updating a mutable field, and
retrieving the customer to confirm the change was applied. Delivers value as a correction
capability.

**Acceptance Scenarios**:

1. **Given** an existing customer, **When** the integrator updates a mutable field with a valid
   value, **Then** the updated customer record is returned and subsequent retrieval reflects the
   change.
2. **Given** an existing customer, **When** the integrator submits an invalid value for a field,
   **Then** the operation fails with an error naming the invalid field and the customer is
   unchanged.

---

### Edge Cases

- What happens when the client is not correctly configured (missing or invalid credentials)? The
  operation MUST fail with an authentication/configuration error rather than silently returning an
  empty result.
- How does the system handle a remote platform outage or timeout? The operation MUST surface a
  clear, actionable error to the caller rather than hanging indefinitely or returning a partial
  record.
- What happens when a list request is made and no customers exist? An empty page MUST be returned,
  not an error.
- What happens when a duplicate customer (by the platform's uniqueness rules) is created? The
  operation MUST surface the platform's conflict/duplicate response as an error to the caller.
- What happens when a page number beyond the available results is requested? An empty page MUST be
  returned.
- What happens when a page size above the maximum (100) is requested? The library MUST reject the
  request with a clear error or clamp the page size to 100, and the chosen behavior MUST be
  documented (see FR-004).
- What happens when an update omits a mutable field? Because update uses full-replace semantics
  (FR-005), the omitted field is cleared/reset — callers MUST send the complete record to preserve
  existing values.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The library MUST expose customer operations as a dedicated customer resource
  reachable through the existing configured client, consistent with how other resources (e.g.
  transactions) are exposed.
- **FR-002**: The library MUST allow an integrator to create a customer by supplying the
  customer's details and MUST return the resulting customer record including its platform-assigned
  identifier.
- **FR-003**: The library MUST allow an integrator to retrieve a single customer by its
  identifier.
- **FR-004**: The library MUST allow an integrator to list customers using page-number pagination,
  exposing both a page number and a page size. When page size is not supplied it MUST default to 20
  records per page, and the library MUST NOT permit a page size greater than 100 (requests above
  the maximum MUST be rejected or clamped to 100 with the behavior documented).
- **FR-005**: The library MUST allow an integrator to update an existing customer using
  full-replace semantics: the caller supplies the complete customer record and any mutable field
  omitted from the update is cleared/reset rather than left unchanged.
- **FR-006**: The library MUST validate, before contacting the remote platform, that the locally
  required customer fields — email, first name, and last name — are present, returning a clear
  error identifying any missing or invalid field without making a remote call. Phone and the
  integrator-supplied reference are optional locally. The remote platform remains free to enforce
  additional required-field and format rules, which MUST be surfaced per FR-009.
- **FR-007**: The library MUST perform every customer operation against the environment (sandbox
  or production) selected on the client, and MUST NOT cross environments.
- **FR-008**: The library MUST authenticate customer requests using the credentials configured on
  the client, without requiring the integrator to supply credentials per call.
- **FR-009**: The library MUST surface remote platform errors (validation, not-found, conflict,
  authentication, and availability errors) to the caller with actionable context, distinguishable
  by error condition.
- **FR-010**: The library MUST NOT log or expose sensitive authentication data or full payment
  card numbers as part of any customer operation, consistent with the project constitution's data
  protection principle.
- **FR-011**: Every customer operation MUST be independently testable against the sandbox
  environment without requiring production credentials.

### Key Entities *(include if feature involves data)*

- **Customer**: Represents a person or organization registered with the Bank of Maldives platform
  that payment activity can be associated with. Attributes include a platform-assigned unique
  identifier and contact details. **Required (validated locally before any remote call)**: email,
  first name, last name. **Optional**: phone, and an integrator-supplied reference for correlation
  with the integrator's own records. A customer may be associated with payment instruments and
  transactions, though managing those is outside this feature.
- **Customer List Page**: Represents a bounded subset of customer records returned for a single
  list request, along with the information needed to request subsequent pages. It is addressed by a
  page number and a page size (default 20, maximum 100 records per page).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An integrator can create a customer and receive a valid customer identifier on the
  first attempt using only the documented required fields, with no undocumented steps.
- **SC-002**: 100% of the four customer operations (create, retrieve, list, update) are
  demonstrable end-to-end against the sandbox environment.
- **SC-003**: Every invalid-input scenario returns an error that names the specific offending
  field, verified for 100% of required fields.
- **SC-004**: No customer operation exposes sensitive authentication data or full card numbers in
  any returned error, log, or record (verified by inspection across all operations).
- **SC-005**: A customer created in sandbox is never visible in production and vice versa,
  confirmed by environment isolation testing.

## Assumptions

- `bml_tokenization` is a client-side integration library that wraps the Bank of Maldives
  tokenization/Connect customer API endpoints, following the same structure as the sibling
  `bml-connect-ruby` gem where a configured client object exposes per-resource classes (such as
  transactions). The customer capability is exposed the same way.
- The customer resource is reached through the already-existing client that manages base URL,
  environment mode (sandbox/production), and authentication credentials (API key / app id); this
  feature does not introduce a new configuration or authentication mechanism.
- Operations in scope for this feature are: create, retrieve-by-identifier, list (paginated), and
  update. Deleting a customer is out of scope unless later confirmed to be supported by the remote
  platform.
- Managing a customer's payment instruments / tokenized cards (attaching, listing, or removing
  tokens) is a separate concern and is out of scope for this feature; this feature manages the
  customer record only.
- The remote platform is the source of truth for customer records, the full set of customer fields,
  and uniqueness rules; the library mirrors that contract rather than defining its own. As an
  exception, the library enforces a minimal local required-field set (email, first name, last name)
  for fail-fast validation per FR-006; the remote platform may enforce additional required or format
  rules on top of this.
- Standard integration-library error handling applies: remote failures are surfaced as errors with
  actionable context rather than swallowed.

## Dependencies

- Requires a configured client (base URL, environment mode, and valid credentials) as already
  established for other resources in the library.
- Requires access to the Bank of Maldives sandbox environment for independent testing of each
  operation.
