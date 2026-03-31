# Feature Specification: CloudEvents Signal Alignment

**Feature Branch**: `005-cloudevents-alignment`  
**Created**: 2026-03-29  
**Status**: Draft  
**Input**: Align signal usage with CloudEvents standard: populate subject fields, standardize PubSub messages as proper signals, define typed signal modules, create signal catalog. Derived from architecture analysis report Section 3.

## User Scenarios & Testing

### User Story 1 - Signals Carry Entity Context via Subject Field (Priority: P1)

All signals emitted by the system populate the CloudEvents `subject` field with the entity they relate to (session, agent, task, workspace). This enables consumers to filter and route signals by entity without parsing data payloads.

**Why this priority**: The `subject` field is the CloudEvents standard mechanism for entity-scoped filtering. Without it, consumers must inspect the opaque `data` payload to determine context, which breaks interoperability with standard CloudEvents tooling.

**Independent Test**: Can be tested by emitting signals of each type and inspecting the resulting struct's `subject` field.

**Acceptance Scenarios**:

1. **Given** an artifact signal emitted for session "sess_123" by agent "agent_abc", **When** the signal is created, **Then** the `subject` field is `/sessions/sess_123` or `/agents/agent_abc`
2. **Given** a task event for task "task_456" in workspace "ws_789", **When** the signal is created, **Then** the `subject` field is `/workspaces/ws_789/tasks/task_456`
3. **Given** a streaming signal for session "sess_123", **When** the signal is created, **Then** the `subject` field references the session

---

### User Story 2 - PubSub Messages Use Signal Envelope (Priority: P1)

All PubSub broadcasts use a consistent signal envelope instead of ad-hoc tuples. Every message broadcast via PubSub carries a type, source, unique ID, and timestamp — enabling audit, replay, and uniform handler patterns.

**Why this priority**: The current mix of signals and raw tuples forces LiveView handlers to pattern-match on two different shapes. Standardizing reduces handler complexity and enables future capabilities like event replay and audit logging.

**Independent Test**: Can be tested by subscribing to PubSub topics and verifying all received messages follow the signal envelope format.

**Acceptance Scenarios**:

1. **Given** a task is created, **When** the PubSub notification is broadcast, **Then** it is a signal with `type: "task.created"`, a unique ID, a timestamp, and the task data in the `data` field
2. **Given** an inter-agent message is sent, **When** the PubSub notification is broadcast, **Then** it follows the same signal envelope format
3. **Given** an artifact update is broadcast, **When** a LiveView receives it, **Then** the handler pattern-matches on a consistent signal shape (same envelope as task and message signals)
4. **Given** the old tuple format `{:task_created, task}`, **When** the migration is complete, **Then** no PubSub broadcast uses raw tuples — all use the signal envelope

---

### User Story 3 - Non-Signal ID Generation Uses Standard UUID (Priority: P2)

Code that generates IDs for non-signal purposes (message IDs, task tracking IDs) uses a general-purpose UUID generator instead of the signal-specific ID function. This avoids semantic confusion between signal identity and general-purpose identity.

**Why this priority**: Minor cleanup that improves code clarity. The system functions correctly either way, but using `Signal.ID.generate!()` for message IDs implies signal semantics where none exist.

**Independent Test**: Can be tested by searching for `Signal.ID.generate!()` usage and verifying each call site is either a signal context or has been migrated.

**Acceptance Scenarios**:

1. **Given** a message being created in the UI layer, **When** it needs a unique ID, **Then** it uses a general-purpose UUID generator — not the signal ID function
2. **Given** a task being tracked for inter-agent communication, **When** it needs a tracking ID, **Then** it uses a general-purpose UUID generator

---

### User Story 4 - Typed Signal Modules Define the Event Catalog (Priority: P2)

Core signal types are defined as typed modules with validated schemas. Each module self-documents its data shape, default source URI, and type string — making the event catalog discoverable and the data contract enforceable.

**Why this priority**: Typed signals provide compile-time validation and serve as living documentation. Important for maintainability as the signal count grows, but the system works without them (signals can be created with bare `Signal.new!` calls).

**Independent Test**: Can be tested by creating signal instances from typed modules and verifying schema validation catches invalid data.

**Acceptance Scenarios**:

1. **Given** a typed signal module for artifact emission, **When** a signal is created with valid data, **Then** the signal has the correct type, default source, and validated data fields
2. **Given** a typed signal module, **When** a signal is created with invalid data (missing required field), **Then** a clear validation error is raised at compile time or runtime
3. **Given** the set of typed signal modules, **When** a developer inspects them, **Then** they can discover all signal types, their data shapes, and their source URIs without reading implementation code

---

### User Story 5 - Signal Event Catalog Documentation (Priority: P3)

A developer reference document lists all signal types used across the ecosystem, their data shapes, which plugins handle them, and which PubSub topics they broadcast on.

**Why this priority**: Documentation that improves developer experience. Not blocking for functionality but becomes increasingly important as the number of signal types and consumers grows.

**Independent Test**: Can be tested by comparing the document against actual signal definitions in the codebase.

**Acceptance Scenarios**:

1. **Given** the signal catalog document, **When** a developer looks up a signal type, **Then** they find its data shape, source, subject pattern, and handling plugins
2. **Given** a new signal type is added to the codebase, **Then** the catalog includes guidance for keeping it updated

---

### Edge Cases

- What happens when a LiveView handler still uses the old tuple pattern after migration? It silently stops receiving messages. Migration must update all handlers atomically.
- What happens when a signal is broadcast to PubSub but no subscriber is listening? Standard PubSub behavior — the message is dropped. No change from current behavior.
- What happens when typed signal validation rejects data at runtime in production? The validation should be strict in dev/test but the raw `Signal.new!` fallback remains available for edge cases.

## Requirements

### Functional Requirements

- **FR-001**: All artifact signals MUST populate the `subject` field with the relevant entity path (session, agent, or workspace identifier)
- **FR-002**: All task-related signals MUST populate the `subject` field with the workspace and task entity path
- **FR-003**: All PubSub broadcast messages MUST use a consistent signal envelope format with `type`, `source`, `id`, and `time` fields
- **FR-004**: No PubSub broadcast MUST use raw tuple format (e.g., `{:task_created, task}`) — all MUST be wrapped in signals
- **FR-005**: Non-signal ID generation (message IDs, tracking IDs) MUST use a general-purpose UUID generator instead of the signal-specific ID function
- **FR-006**: Typed signal modules MUST be defined for core signal types using the framework's typed signal definition mechanism
- **FR-007**: Each typed signal module MUST include a data schema with required/optional field annotations
- **FR-008**: A signal event catalog document MUST be created listing all signal types, data shapes, handling plugins, and PubSub topics
- **FR-009**: LiveView handlers MUST be updated to use the new consistent signal envelope pattern
- **FR-010**: The migration from tuple format to signal format MUST update all handlers atomically to avoid silent message drops

### Key Entities

- **Signal Envelope**: The standardized message format for all PubSub broadcasts — a Jido.Signal struct with type, source, id, time, and data fields.
- **Typed Signal Module**: A module that defines a signal type with a validated data schema, default source URI, and type string.
- **Signal Catalog**: A developer reference document listing all signal types in the ecosystem.
- **Subject Field**: The CloudEvents field identifying the entity a signal relates to (e.g., `/sessions/{id}`, `/workspaces/{id}/tasks/{id}`).

## Success Criteria

### Measurable Outcomes

- **SC-001**: Every signal emitted by the system includes a meaningful `subject` field that identifies the relevant entity
- **SC-002**: PubSub message handlers use a single, consistent pattern for all message types — no mixed tuple/signal matching
- **SC-003**: Developers can discover all signal types and their data contracts by reading the typed signal modules or the catalog document
- **SC-004**: Zero raw-tuple PubSub broadcasts remain after migration
- **SC-005**: The full test suite passes after all PubSub handler migrations with zero regressions
- **SC-006**: New signals added in the future follow the established typed module pattern with documented schema

## Assumptions

- The jido_signal framework provides `use Jido.Signal` for typed signal module definitions with NimbleOptions schema validation. This is confirmed in the jido_signal v2.0.0 codebase.
- `Uniq.UUID.uuid7()` is available in the dependency tree (via jido_signal) for general-purpose UUID generation.
- All PubSub handlers are in LiveView modules (jido_murmur_web) — no external consumers subscribe to these topics yet. This bounds the migration scope.
- The five ad-hoc tuple patterns identified in the analysis are the complete set: `{:artifact_update, ...}`, `{:agent_signal, ...}`, `{:message_completed, ...}`, `{:task_created, ...}`, `{:new_message, ...}`.
- CloudEvents extensions (e.g., `murmursessionid`) are deferred — not part of this feature's scope.
