# Feature Specification: Platform Infrastructure Improvements

**Feature Branch**: `006-platform-improvements`  
**Created**: 2026-03-29  
**Status**: Draft  
**Input**: Platform infrastructure improvements: standardize PubSub topics, thread workspace_id through plugins, add startup config validation, add telemetry to jido_tasks, typed agent profile behaviour. Derived from architecture analysis report Section 4.

## User Scenarios & Testing

### User Story 1 - Consistent PubSub Topic Naming (Priority: P1)

All PubSub topics follow a single hierarchical naming convention that includes workspace context. Topic construction is centralized in a helper module, eliminating string duplication and inconsistency across the codebase.

**Why this priority**: Inconsistent topics make it hard to reason about subscriptions, debug message routing, and implement workspace-level features. Fixing this before v1.0 avoids breaking changes after publish.

**Independent Test**: Can be tested by searching all PubSub topic references and verifying they use the centralized helper functions with consistent format.

**Acceptance Scenarios**:

1. **Given** a centralized topic helper module, **When** any part of the system constructs a PubSub topic, **Then** it uses a helper function rather than inline string interpolation
2. **Given** the new topic format, **When** agent streaming, artifact, and message topics are constructed, **Then** all include workspace context in a consistent hierarchical format
3. **Given** the old topic format (e.g., `"agent_artifacts:#{session_id}"`), **When** migration is complete, **Then** no code references the old format

---

### User Story 2 - Plugins Receive Workspace Context (Priority: P1)

All plugins (artifact, streaming) have access to workspace_id from the agent state, enabling workspace-scoped PubSub topics and future multi-workspace features.

**Why this priority**: This is a prerequisite for standardized PubSub topics (User Story 1) and future workspace-scoped features (shared artifacts). Without it, plugins can only broadcast to session-scoped topics.

**Independent Test**: Can be tested by running a plugin's signal handler with mock agent state containing workspace_id and verifying the broadcast uses workspace-scoped topics.

**Acceptance Scenarios**:

1. **Given** an agent with workspace_id in its state, **When** the artifact plugin broadcasts, **Then** the PubSub topic includes the workspace_id
2. **Given** an agent with workspace_id in its state, **When** the streaming plugin broadcasts, **Then** the PubSub topic includes the workspace_id
3. **Given** an agent without workspace_id (backward compatibility), **When** a plugin attempts to broadcast, **Then** it falls back to a session-only topic or raises a clear error

---

### User Story 3 - Clear Error on Missing Configuration (Priority: P2)

When a developer starts their application without required configuration (repo, pubsub, jido_mod, otp_app), the system raises a clear, actionable error message at startup — not a cryptic crash deep in the call stack.

**Why this priority**: First-run experience improvement. Config errors are the most common setup issue, and a clear message with remediation instructions saves developer time.

**Independent Test**: Can be tested by removing required config keys and verifying the startup error message is clear and includes remediation instructions.

**Acceptance Scenarios**:

1. **Given** missing `:repo` configuration, **When** the application starts, **Then** the error message names the missing key and suggests running the install command
2. **Given** missing `:pubsub` configuration, **When** the application starts, **Then** the error message names the missing key and shows the expected config format
3. **Given** all required configuration present, **When** the application starts, **Then** startup proceeds without validation messages

---

### User Story 4 - Telemetry Events for Task Operations (Priority: P3)

Task operations (create, update, list) emit telemetry events for observability, enabling dashboards and monitoring. This brings parity with jido_murmur which already has telemetry instrumentation.

**Why this priority**: Nice-to-have for observability. The system functions without telemetry, but monitoring dashboards and performance debugging benefit from it.

**Independent Test**: Can be tested by attaching a telemetry handler and performing task operations, then verifying events are emitted with expected measurements and metadata.

**Acceptance Scenarios**:

1. **Given** a telemetry handler attached, **When** a task is created, **Then** a telemetry event is emitted with the task ID and creation metadata
2. **Given** a telemetry handler attached, **When** a task is updated, **Then** a telemetry event is emitted with the task ID, old status, and new status
3. **Given** no telemetry handler attached, **When** task operations occur, **Then** the system functions normally with no overhead

---

### User Story 5 - Typed Agent Profile Behaviour (Priority: P3)

Agent profiles implement a defined behaviour that declares required callbacks (name, description, system_prompt, tools, plugins). The compiler validates that all required callbacks are implemented, catching errors before runtime.

**Why this priority**: Defensive improvement. Current convention-based profiles work, but as the profile count grows, compile-time validation prevents silent misconfiguration.

**Independent Test**: Can be tested by creating a profile module that omits a required callback and verifying a compiler warning is raised.

**Acceptance Scenarios**:

1. **Given** a profile module that implements all required callbacks, **When** the module compiles, **Then** no warnings are raised
2. **Given** a profile module missing the `tools` callback, **When** the module compiles, **Then** a compiler warning indicates the missing callback
3. **Given** the behavior definition, **When** the agent catalog loads profiles, **Then** it can call behaviour callbacks directly instead of relying on module attribute conventions

---

### Edge Cases

- What happens when existing PubSub subscribers (LiveViews) are still listening on old topic formats during a rolling migration? Topic migration must be coordinated — update subscribers before publishers, or support both formats temporarily.
- What happens when config validation runs in a test environment where not all config is set? Test environments may need their own validation rules or opt-out mechanism.
- What happens when an existing profile module doesn't implement the new behaviour? A deprecation period where both convention-based and behaviour-based profiles are supported.

## Requirements

### Functional Requirements

- **FR-001**: A centralized topic helper module MUST provide functions for constructing all PubSub topics used in the system
- **FR-002**: All PubSub topics MUST include workspace context in a consistent hierarchical format
- **FR-003**: No inline PubSub topic string interpolation MUST remain in the codebase — all MUST use the helper module
- **FR-004**: Artifact and streaming plugins MUST extract workspace_id from agent state and include it in PubSub broadcasts
- **FR-005**: Plugins MUST handle missing workspace_id gracefully (fallback or clear error)
- **FR-006**: Application startup MUST validate required configuration keys (repo, pubsub, jido_mod, otp_app) and raise clear error messages with remediation instructions
- **FR-007**: Task operations (create, update, list) MUST emit telemetry events with operation metadata
- **FR-008**: Telemetry events MUST follow the established naming convention consistent with existing jido_murmur telemetry
- **FR-009**: An agent profile behaviour MUST define callbacks for name, description, system_prompt, tools, plugins, and opts

### Key Entities

- **Topic Helper Module**: A centralized module providing functions for all PubSub topic construction, ensuring consistency and avoiding string duplication.
- **Agent Profile Behaviour**: A behaviour module defining the required callbacks for agent profile modules, enabling compile-time validation.
- **Config Validator**: A startup-time validation function that checks for required configuration keys and raises actionable error messages.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All PubSub topics in the codebase are constructed via the centralized helper module — zero inline topic strings remain
- **SC-002**: All PubSub topics include workspace context in a consistent format
- **SC-003**: Missing configuration produces a clear error message naming the specific key and remediation steps — not a deep stack trace
- **SC-004**: Task operations emit telemetry events that can be captured by standard telemetry handlers
- **SC-005**: Profile modules that omit required callbacks produce compiler warnings
- **SC-006**: The full test suite passes after all changes with zero regressions

## Assumptions

- Workspace_id is available in the agent state. If not currently stored there, the agent initialization flow must be updated to include it.
- The existing telemetry infrastructure (`:telemetry` dependency) is already in the project and used by jido_murmur.
- PubSub topic migration can be done in a single release (no rolling deployment concern) since the application is not yet deployed externally.
- The behaviour adoption for existing profiles is non-breaking — profiles can adopt the behaviour gradually.
