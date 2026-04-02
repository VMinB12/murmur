# Spec: LLM Observability & Tracing

## User Stories

### US-1: Inspect a single react loop end to end (Priority: P1)

**As a** developer debugging agent behavior, **I want** each executed react loop to appear as its own trace with nested LLM and tool activity, **so that** I can inspect exactly what the agent did during one turn of work.

**Independent test**: Send one message to an idle agent that performs at least one tool call; the observability backend shows exactly one new trace for that turn, with one root turn span and nested child spans for all LLM and tool work.

### US-2: Preserve full developer-visible inputs and outputs (Priority: P1)

**As a** developer diagnosing bad agent behavior, **I want** traces to include the exact request and response payloads the runtime used, plus token, latency, and error data, **so that** I can understand what the model and tools actually saw and returned.

**Independent test**: Run a turn with a prompt, a streamed or non-streamed model response, and a tool call; the trace data exposes the effective LLM input messages, assistant output, tool arguments, tool result, usage, duration, and any errors.

### US-3: Keep steering messages inside the active turn (Priority: P1)

**As a** developer debugging inter-agent coordination, **I want** steering messages that are injected while an agent is already running to stay within the active trace, **so that** one turn's causal chain is not split across multiple traces.

**Independent test**: Start a long-running turn, inject a steering message while the agent is busy, and verify that no second root trace is created while the active trace records the injected message and the downstream work it triggered.

### US-4: Start a fresh trace when a previously idle agent begins work (Priority: P1)

**As a** developer inspecting agent scheduling behavior, **I want** a new trace whenever an idle agent starts a new react loop, even if the trigger came from another agent, **so that** trace boundaries match actual execution boundaries.

**Independent test**: Send a tell message to an idle target agent and verify that the receiving agent creates a new trace linked back to the originating agent or trace.

### US-5: Group turn traces into one long-lived agent conversation session (Priority: P1)

**As a** developer reviewing an agent over time, **I want** separate turn traces for that agent to be grouped into one session, **so that** I can inspect both individual turns and the broader conversation history without collapsing them into one trace.

**Independent test**: Send two sequential messages to the same agent; the trace view shows two distinct traces and the session view groups both traces under the same long-lived conversation session.

### US-6: Correlate work across a workspace or team without flattening trace boundaries (Priority: P2)

**As a** developer investigating a multi-agent workflow, **I want** traces to carry team or workspace correlation metadata and cross-agent causation links, **so that** I can reconstruct collaboration across agents without turning all team activity into one giant trace.

**Independent test**: Run a workflow involving multiple agents in the same workspace; traces remain separate per agent turn and can still be filtered or linked together through shared correlation metadata and causation fields.

## Acceptance Criteria

- [ ] Each root trace represents exactly one executed react loop, not each individual inbound message.
- [ ] If multiple pending messages are drained and processed in one loop, they appear within the same root trace.
- [ ] The root trace exposes the executing agent identity and enough context to determine which conversation or session it belongs to.
- [ ] Every LLM call executed during the loop appears as a child span with the effective input messages sent to the model, the returned output available to the runtime, latency, usage, finish state, and error details when applicable.
- [ ] Streamed LLM responses expose the accumulated assistant output content in traces instead of only a byte-count or placeholder summary.
- [ ] Every tool execution appears as a child span with tool identity, input, output, duration, retries or timeout state, and errors when applicable.
- [ ] Steering messages injected while an agent is already running do not create a new root trace.
- [ ] When an injected steering message changes the active turn, that change is visible inside the active trace.
- [ ] A message that starts work on an idle agent creates a new root trace for the receiving agent.
- [ ] Cross-agent work started by another agent includes enough causation metadata to identify the originating agent and originating trace or interaction.
- [ ] Multiple traces belonging to the same long-lived agent conversation share one stable session identifier.
- [ ] Team or workspace correlation metadata is attached consistently enough for developers to filter related traces across agents.
- [ ] The resulting trace and session model renders correctly in Arize Phoenix's trace-oriented and session-oriented views.
- [ ] The observability model avoids duplicate traces for the same react loop when multiple instrumentation layers observe the same underlying work.
- [ ] Developers can inspect exact input and output content by default in development-oriented environments, with any redaction or suppression behavior being explicit and configurable.

## Scope

### In Scope

- A Murmur-owned observability model for agent turns, LLM calls, tool calls, injected messages, and errors
- Clear runtime semantics for spans, traces, sessions, and cross-agent correlation
- Trace data that supports deep debugging of agent input, output, token usage, latency, and failures
- Compatibility with Arize Phoenix trace and session views
- Replacement of the current AgentObs-based tracing path where needed to achieve the desired runtime semantics

### Out of Scope

- A custom Murmur observability UI separate from existing backend tooling
- Generic application performance monitoring beyond agent, LLM, and tool execution flows
- Multi-tenant analytics, billing dashboards, or long-term warehouse-style reporting
- Full productization of arbitrary third-party tracing backends beyond maintaining clean exportable semantics