# Feature Specification: LLM OpenTelemetry Tracing

**Feature Branch**: `007-llm-otel-tracing`  
**Created**: 2025-07-24  
**Status**: Draft  
**Input**: User description: "Rich LLM observability tracing — every LLM call surfaces input messages, output messages, token usage, tool calls, and agent/session context in the observability UI so developers can inspect, debug, and optimize AI agent conversations end-to-end."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View LLM Conversation Content in Traces (Priority: P1)

As a developer debugging an agent conversation, I open the observability UI and click on an LLM trace. I can see the full conversation: the input messages sent to the model (system prompt, user message, prior assistant messages, tool results) and the model's output response. Each message shows its role (system, user, assistant, tool) and content. This lets me verify that prompts are correct, context is being passed properly, and the model is responding as expected.

**Why this priority**: Without input/output message visibility, traces are opaque — developers cannot debug prompt issues, hallucinations, or context window problems. This is the core gap today: traces appear but are "empty."

**Independent Test**: Send a message to an agent, open the observability UI, click the resulting LLM trace, and verify that input messages with roles and content are displayed, along with the model's output response text.

**Acceptance Scenarios**:

1. **Given** a developer sends a message to an agent, **When** they view the resulting LLM trace, **Then** they see each input message with its role (system, user, assistant, tool) and full content text.
2. **Given** a developer views an LLM trace, **When** the model returned a text response, **Then** the output message is displayed with the assistant role and full content.
3. **Given** a multi-turn agent conversation with tool use, **When** a developer views any LLM call in the sequence, **Then** the input messages include all prior context (system prompt, user messages, assistant responses, tool results) that were sent to the model for that call.

---

### User Story 2 - Track Token Usage and Cost Per LLM Call (Priority: P2)

As a developer monitoring costs, I view an LLM trace and see the exact token counts: how many prompt tokens were sent, how many completion tokens the model generated, and the total. The observability UI aggregates these across all LLM calls in a conversation, giving me visibility into which conversations or agents are expensive.

**Why this priority**: Token usage directly affects operational costs. Without per-call token breakdowns, developers cannot identify expensive prompts, optimize context windows, or set usage budgets.

**Independent Test**: Trigger an agent conversation, view the trace, and verify prompt token count, completion token count, and total token count are displayed for each LLM call.

**Acceptance Scenarios**:

1. **Given** an LLM call completes, **When** a developer views the trace, **Then** prompt token count, completion token count, and total token count are visible.
2. **Given** multiple LLM calls occur in a conversation, **When** a developer views the conversation trace tree, **Then** each individual call shows its own token counts.

---

### User Story 3 - Inspect Tool Calls Within LLM Traces (Priority: P2)

As a developer debugging agent tool use, I view an LLM trace and see when the model requested a tool call, what arguments it passed, and what the tool returned. This helps me diagnose issues where agents select wrong tools, pass incorrect arguments, or misinterpret tool results.

**Why this priority**: Tool calling is a core part of ReAct agent behavior. Without visibility into tool call requests and results within the LLM context, developers cannot debug the agent's reasoning loop.

**Independent Test**: Trigger an agent conversation that involves tool use, view the trace, and verify the tool call name, arguments, and result are visible within the LLM call context.

**Acceptance Scenarios**:

1. **Given** an LLM call includes a tool call in its output, **When** a developer views the trace, **Then** the tool name and arguments are visible as part of the assistant output message.
2. **Given** a subsequent LLM call includes tool results in its input, **When** a developer views the trace, **Then** tool result messages with the tool name and returned content are visible.

---

### User Story 4 - Group Traces by Conversation Session (Priority: P3)

As a developer investigating a specific user conversation, I filter or group traces by session so I see all LLM calls, tool invocations, and agent actions that belong to that conversation in one view. This provides an end-to-end timeline of what happened during a single user interaction.

**Why this priority**: Without session grouping, traces from different conversations are interleaved, making it difficult to follow the flow of a specific interaction. Session context turns individual traces into a coherent conversation narrative.

**Independent Test**: Conduct two separate agent conversations, open the observability UI, filter by session, and verify that each session shows only its own traces.

**Acceptance Scenarios**:

1. **Given** a developer has multiple active conversations, **When** they filter traces by session in the observability UI, **Then** only traces belonging to the selected conversation are shown.
2. **Given** a workspace-based conversation, **When** traces are emitted, **Then** all traces from the same workspace share a common session identifier.

---

### User Story 5 - Identify Which Agent Made Each LLM Call (Priority: P3)

As a developer working with multiple agents (e.g., "Bob", "Alice"), I view an LLM trace and can see which agent initiated it. This helps me understand agent-specific behaviors, compare performance across agents, and debug issues with a specific agent's configuration.

**Why this priority**: In a multi-agent system, knowing which agent produced a trace is essential for targeted debugging. Without agent identity, all LLM calls look the same regardless of which agent made them.

**Independent Test**: Send messages to two different agents, view the resulting traces, and verify each trace shows the originating agent's name.

**Acceptance Scenarios**:

1. **Given** an LLM call is made by a specific agent, **When** a developer views the trace, **Then** the agent's display name is visible as a trace attribute.
2. **Given** multiple agents are active, **When** a developer filters traces by agent name, **Then** only traces from that agent are shown.

---

### User Story 6 - Trace Streaming LLM Calls Reliably (Priority: P1)

As a developer, when an agent makes a streaming LLM call (where the response arrives token-by-token), the trace is captured completely — both the start of the request and the final result including full output text and token counts. Streaming calls must produce the same quality of trace data as non-streaming calls.

**Why this priority**: The application primarily uses streaming LLM calls for real-time user experience. If streaming traces are incomplete or missing, observability covers only a tiny fraction of actual LLM usage. This is a prerequisite for all other stories.

**Independent Test**: Send a message to an agent (which uses streaming), view the trace, and verify it contains input messages, output text, and token counts — identical in richness to a non-streaming trace.

**Acceptance Scenarios**:

1. **Given** an agent makes a streaming LLM call, **When** a developer views the trace, **Then** the trace contains the complete output text (not partial or empty).
2. **Given** a streaming LLM call completes, **When** the trace is exported, **Then** token counts (prompt, completion, total) are present and accurate.
3. **Given** a streaming LLM call fails mid-stream, **When** a developer views the trace, **Then** the trace is marked as an error with a descriptive error message.

---

### Edge Cases

- What happens when an LLM call times out before any response is received? The trace must still be closed with an error status and a meaningful error message.
- What happens when the observability backend is unavailable? Tracing failures must not crash the application or degrade user-facing performance.
- What happens when an LLM response contains no content (empty assistant message)? The trace must still be recorded with empty output rather than being silently dropped.
- What happens during concurrent LLM calls from different agents in the same process? Each call must produce its own independent, correctly attributed trace.
- What happens when input messages are very large (e.g., long context windows with many prior messages)? The system should still record them without truncation, within reasonable memory bounds.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST record the full list of input messages (role and content for each) on every LLM call trace.
- **FR-002**: System MUST record the model's output response (role and content) on every LLM call trace.
- **FR-003**: System MUST record token usage on every LLM call trace: prompt tokens, completion tokens, and total tokens.
- **FR-004**: System MUST record the model identifier (e.g., "gpt-5-mini") on every LLM call trace.
- **FR-005**: System MUST reliably trace streaming LLM calls end-to-end, even when the request initiation and response completion happen in different execution contexts.
- **FR-006**: System MUST record tool call information (tool name, arguments) when the model requests a tool call as part of its output.
- **FR-007**: System MUST record tool result messages (tool name, returned content) when they appear in the input to a subsequent LLM call.
- **FR-008**: System MUST attach a session identifier to every trace so that all traces from the same conversation can be grouped together.
- **FR-009**: System MUST attach the originating agent's display name to every LLM call trace.
- **FR-010**: System MUST use the OpenInference semantic conventions for all trace attributes so the observability UI can parse and display them correctly.
- **FR-011**: System MUST NOT crash or degrade user-facing functionality when tracing fails (e.g., export errors, backend unavailability).
- **FR-012**: System MUST close every opened trace span, even when the LLM call fails with an error or exception, recording the error details on the span.
- **FR-013**: System MUST NOT log or export sensitive credentials (API keys, tokens) in trace attributes. Input/output message content is acceptable as it is needed for debugging.

### Key Entities

- **LLM Call Trace**: Represents a single invocation of a language model. Key attributes: model name, input messages, output messages, token counts, latency, status, session ID, agent name.
- **Message**: An individual message in the LLM conversation context. Attributes: role (system, user, assistant, tool), content text, optional tool call metadata.
- **Tool Call**: A model-requested tool invocation. Attributes: tool name, arguments, associated LLM trace.
- **Session**: A logical grouping of related traces belonging to one user conversation/workspace.
- **Agent**: The AI agent that initiated the LLM call. Attributes: display name, unique identifier.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of LLM calls made by agents produce a trace with visible input and output message content in the observability UI.
- **SC-002**: Developers can view the exact prompt messages sent to any LLM call within 3 clicks from the trace list.
- **SC-003**: Token usage (prompt, completion, total) is accurately reported on every LLM trace, matching the values returned by the model provider.
- **SC-004**: All traces from a single conversation are retrievable by filtering on session, with zero trace leakage between sessions.
- **SC-005**: Streaming LLM calls produce traces with the same attribute completeness as non-streaming calls — no missing output text or token counts.
- **SC-006**: Tracing adds less than 50ms of overhead per LLM call to application response time.
- **SC-007**: Application uptime and user-facing behavior are unaffected when the observability backend is stopped or unreachable.

## Assumptions

- The Arize Phoenix observability backend is running locally via Docker during development and accepts traces via standard OTLP protocol.
- The application primarily uses streaming LLM calls; non-streaming calls are a secondary path but must also be traced.
- The existing agent framework emits telemetry events that include the information needed for tracing (model, messages, token usage); no changes to the model provider APIs are assumed.
- OpenInference semantic conventions are the expected attribute format for the observability UI to render rich LLM trace views (message bubbles, token dashboards, tool call inspection).
- Sensitive data redaction of API keys and credentials is already handled upstream; message content (prompts and responses) is acceptable to include in traces for debugging purposes.
- Multiple agent types may be active concurrently in the same application, each producing independent traces.
- Session identity maps to the existing workspace concept — one workspace equals one session.
