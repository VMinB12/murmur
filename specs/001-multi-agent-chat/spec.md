# Feature Specification: Multi-Agent Chat Interface

**Feature Branch**: `001-multi-agent-chat`  
**Created**: 2026-03-25  
**Status**: Draft  
**Input**: User description: "Multi-Agent Chat Interface allowing users to dynamically construct a team of AI agents for a workspace with real-time streaming, agent-to-agent communication, and side-by-side column layout"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Send a Message and Receive a Streamed Response (Priority: P1)

A user opens a workspace containing at least one active agent. They type a message into that agent's input box and press send. The agent's response appears token-by-token in real time inside the agent's chat column. When the response is complete, the agent's own conversation history is persisted to the database. Each agent session maintains its own independent history — there is no shared or merged history across agents.

**Why this priority**: This is the foundational interaction loop. Without single-agent chat and streaming, no other feature has value.

**Independent Test**: Can be fully tested by opening a workspace with one agent, sending a message, and confirming a streamed reply appears and is saved to the database.

**Acceptance Scenarios**:

1. **Given** a workspace with one active agent, **When** the user types a message and submits, **Then** the message appears in the chat column immediately as a user message.
2. **Given** a submitted user message, **When** the agent begins responding, **Then** tokens appear incrementally in the agent's chat column without a full page refresh.
3. **Given** an agent that has finished responding, **When** the response completes, **Then** that agent's conversation history is persisted to the database independently.
4. **Given** an agent that is currently generating a response, **When** the user views the agent column, **Then** a visible busy/thinking indicator is shown.

---

### User Story 2 - Build a Team of Agents in a Workspace (Priority: P2)

A user creates or opens a workspace and adds multiple predefined agents from a catalog. Each agent appears as its own chat column in a side-by-side layout. The user can also remove an agent from the workspace.

**Why this priority**: Multi-agent team construction is the core differentiator of Murmur. It builds on top of the single-agent chat established in P1.

**Independent Test**: Can be tested by creating a workspace, adding two agents from the catalog, verifying both columns appear, sending a message to each independently, and then removing one agent.

**Acceptance Scenarios**:

1. **Given** an empty workspace, **When** the user opens the agent catalog and selects an agent, **Then** a new chat column appears for that agent.
2. **Given** a workspace with two agents, **When** the user sends a message to Agent A, **Then** only Agent A responds; Agent B's column is unaffected.
3. **Given** a workspace with an active agent, **When** the user removes that agent, **Then** the agent's column disappears and the remaining agents reflow to fill the space.
4. **Given** a workspace with agents, **When** the user refreshes the browser, **Then** all previously added agents and their histories are restored.

---

### User Story 3 - Agents Communicate with Each Other (Priority: P3)

While responding to a user, an agent decides it needs input from another agent in the same workspace. It uses the "tell" capability to send a message to the target agent. The message appears in the target agent's chat column, and the target agent processes it and responds.

**Why this priority**: Inter-agent communication is the collaboration feature that distinguishes Murmur from parallel independent chats. It requires both P1 (single-agent chat) and P2 (multi-agent workspace) to be in place.

**Independent Test**: Can be tested by adding two agents to a workspace, prompting Agent A with a task that requires Agent B's expertise, and verifying a message appears in Agent B's column from Agent A and triggers a response.

**Acceptance Scenarios**:

1. **Given** a workspace with Agent A and Agent B both idle, **When** Agent A uses "tell" to send a message to Agent B, **Then** the message appears in Agent B's column prefixed with Agent A's name.
2. **Given** Agent B receives a "tell" message while idle, **When** the message is delivered, **Then** Agent B automatically begins processing it and streams a response.
3. **Given** Agent B is currently busy responding, **When** Agent A sends a "tell" message, **Then** the message is held and injected into Agent B's context before its next processing step.
4. **Given** an inter-agent message exchange, **When** each agent individually finishes processing, **Then** that agent's own history is persisted immediately — there is no waiting for the other agent to finish.

---

### User Story 4 - Reconnect and Resume After Disconnect (Priority: P4)

A user is watching a streamed response when their browser loses connection (e.g., network hiccup, closing and reopening the tab). Agent execution continues server-side regardless of browser state — agents are not dependent on the user being connected. When the user reconnects, the current state of all agent sessions is restored from the backend, and any agents still working continue streaming as if the user never left.

**Why this priority**: Resilient session recovery is essential for a real-time streaming application. Users must not lose context due to transient network issues. Agents must be autonomous — they work for the user, not only while the user watches.

**Independent Test**: Can be tested by starting an agent response, disconnecting the browser's WebSocket, waiting for the response to complete server-side, reconnecting, and verifying the full response is visible and any still-running agents continue streaming.

**Acceptance Scenarios**:

1. **Given** an agent is streaming a response, **When** the user's browser disconnects, **Then** the agent continues executing server-side without interruption.
2. **Given** an agent completed a response while the user was disconnected, **When** the user reconnects, **Then** the user sees the complete response immediately.
3. **Given** an agent is still generating a response when the user reconnects, **When** the browser re-establishes its connection, **Then** the user sees tokens continuing to stream in real time as if they never left.
4. **Given** multiple agents in a workspace, **When** the user reconnects, **Then** all agent columns are restored with their current histories and statuses (idle/busy).

---

### Edge Cases

- What happens when the user sends a message to an agent that is already busy? The message is injected into the agent's pending messages, identical to how the "tell" mechanism works. This reflects a core design principle: there is very little that distinguishes humans from agents — both interact with agents the same way.
- What happens when an agent's "tell" targets an agent that has been removed from the workspace? The tool call should fail gracefully and the originating agent should be informed the target is unavailable.
- What happens when a workspace has no agents? The UI should display a clear empty state with guidance to add an agent from the catalog.
- What happens when the user adds the same agent profile twice? This is allowed. When adding an agent, the user gives it a display name. The same agent profile can be added multiple times, but each display name MUST be unique within the workspace. The system rejects duplicate display names at add time.
- What happens when an inter-agent "tell" creates a circular loop (Agent A tells B, B tells A, etc.)? The system should limit the depth of chained inter-agent invocations to prevent runaway loops.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a catalog of predefined agent profiles, each with a name, description, system prompt, fixed model, and available tools
- **FR-002**: Users MUST be able to create a workspace that acts as a container for multiple agent sessions
- **FR-003**: Users MUST be able to add agents from the catalog to a workspace, providing a display name for each, creating an independent chat session
- **FR-004**: Users MUST be able to remove an agent from a workspace, ending its session
- **FR-005**: Each agent session MUST display as its own scrollable chat column in a side-by-side horizontal layout
- **FR-006**: Each agent column MUST have its own independent text input for sending messages
- **FR-007**: Agent responses MUST stream token-by-token to the user interface in real time
- **FR-008**: Each agent MUST persist its own conversation history to the database after each complete agent turn (one full request→response cycle, including all tool calls within that cycle) — not per-token, not per individual tool step, and not waiting for other agents
- **FR-009**: Agents MUST have access to a "tell" capability that sends a fire-and-forget message to another agent in the same workspace
- **FR-010**: Inter-agent messages MUST appear in the receiving agent's history prefixed with the sender's name
- **FR-011**: When a "tell" message arrives for an idle agent, the system MUST immediately trigger the agent to process it
- **FR-012**: When a "tell" message arrives for a busy agent, the system MUST queue the message and inject it before the agent's next processing step
- **FR-013**: The system MUST restore agent session state (history, status) when a user's browser reconnects after a disconnect
- **FR-013a**: Agent execution MUST continue server-side regardless of whether the user's browser is connected
- **FR-013b**: When a user reconnects to a workspace with still-running agents, the system MUST resume streaming tokens to the user in real time
- **FR-014**: The system MUST display a visible indicator when an agent is busy/thinking
- **FR-015**: The system MUST limit the depth of chained inter-agent invocations to prevent runaway loops (maximum 5 hops per originating user message)
- **FR-016**: Each agent column MUST display the agent's user-given name, profile type, model, and a visual identifier (e.g., colored header)
- **FR-017**: When a user sends a message to a busy agent, the system MUST inject it into the agent's pending messages (identical to "tell" behavior) rather than blocking or disabling input
- **FR-018**: Multiple instances of the same agent profile MUST be allowed within a single workspace, each with a user-given display name that is unique within the workspace
- **FR-019**: The system MUST enforce unique display names per workspace and reject adding an agent with a display name that already exists in that workspace

### Key Entities

- **Workspace**: A logical container for a user's multi-agent session. Has a name and references zero or more Agent Sessions. Acts as the top-level scope for inter-agent communication routing.
- **Agent Profile**: A predefined template describing an agent's identity — name, system prompt, fixed model, and available tools. Agent Profiles are read-only and shared across all workspaces.
- **Agent Session**: An active instance of an Agent Profile within a Workspace. Has a user-given display name. Holds its own independent conversation history and current status (idle/busy). Multiple sessions of the same Agent Profile are allowed in one Workspace.
- **Message**: A single entry in an Agent Session's conversation history. Has a role (user, assistant, tool_call, tool_result), content, and optional tool metadata. Messages from other agents via "tell" appear with role "user" and a name prefix.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can add an agent to a workspace and receive a streamed response within 3 seconds of sending a message
- **SC-002**: Token streaming is visually smooth with no perceptible lag between received tokens appearing on screen
- **SC-003**: Users can construct a team of 5 concurrent agents in a single workspace without UI lag or degradation
- **SC-004**: Inter-agent "tell" messages are delivered and trigger processing within 1 second of being dispatched
- **SC-005**: After a browser disconnect and reconnect, the user's full workspace state is restored within 2 seconds
- **SC-006**: 90% of first-time users can successfully add an agent and send a message without external guidance
- **SC-007**: Conversation history persists across page refreshes — no messages are lost after a completed response cycle

## Assumptions

- Users have a modern browser with WebSocket support and stable internet connectivity
- Multiple sessions of the same agent profile are allowed in a workspace; the user assigns a unique display name when adding each agent; uniqueness is enforced by the system
- Authentication and user accounts are out of scope for v1; the application runs as a single-user local or dev-mode instance
- The agent catalog is hardcoded at application startup and does not change at runtime; dynamic agent creation is a future feature
- Mobile and tablet layouts are out of scope for v1; the side-by-side column layout targets desktop viewports (≥1024px)
- LLM API keys and endpoint configuration are managed via application environment/config, not through the UI
- The maximum number of agents per workspace is capped at 8 to keep the horizontal layout usable
- Inter-agent "tell" loop depth is capped at 5 hops per originating user message to prevent infinite recursion

## Clarifications

### Session 2026-03-25

- Q: Should Story 1 address per-agent history persistence? → A: Yes, each agent persists its own independent history; no shared exchange concept. Belongs in Story 1 as it is foundational.
- Q: Story 3 scenario 4 says "both agents finish" — when does persistence happen? → A: Each agent persists its own history immediately upon its own completion, not when all agents collectively finish.
- Q: What happens when a user sends a message to a busy agent? → A: Message is injected into pending messages, identical to "tell" behavior. Core principle: humans and agents interact with agents the same way.
- Q: Should duplicate agent profiles be allowed in a workspace? → A: Yes, allowed. User gives a display name when adding. No uniqueness enforcement.
- Q: Should agents continue working when the user disconnects? → A: Yes, agents execute server-side regardless of browser state. On reconnect, still-running agents resume streaming to the user.
- Q: Persist after every model/tool step, or after each complete agent turn, or only when fully idle? → A: After each complete agent turn (Option B). One full request→response cycle including tool calls. Balances durability with write efficiency.
- Q: Should agent display names be unique within a workspace? → A: Yes. Unique display names are enforced by the system. This enables unambiguous routing for the "tell" tool — agents reference each other by display name.
