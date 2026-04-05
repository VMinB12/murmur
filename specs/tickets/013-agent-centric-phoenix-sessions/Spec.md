# Spec: Agent-Centric Phoenix Sessions

## User Stories

### US-1: One Phoenix session row per agent (Priority: P1)

**As a** developer inspecting Murmur activity in Arize Phoenix, **I want** Phoenix Sessions to show one stable row per agent session, **so that** all work performed by a given agent is grouped under that agent regardless of pauses between messages.

**Independent test**: Send multiple direct messages to the same agent over a long time gap and verify all resulting traces remain grouped under one Phoenix session row keyed by that agent.

### US-2: One root trace per executed react loop (Priority: P1)

**As a** developer debugging agent behavior, **I want** every executed react loop to appear as its own trace, **so that** trace boundaries match real runtime execution rather than inbound message count.

**Independent test**: Send a message to an idle agent, then deliver follow-up input while the agent is still active, and verify the running loop still has only one root trace.

### US-3: Remove discussion and interaction identifiers from the canonical model (Priority: P1)

**As a** Murmur maintainer, **I want** Phoenix session grouping and observability metadata to stop depending on inferred discussions, `interaction_id`, and inactivity rollover, **so that** the runtime model stays simple and stable.

**Independent test**: Inspect direct and programmatic ingress plus exported span attributes and verify session grouping works without `ConversationCache`, `:conversation_session_timeout_ms`, or `murmur.interaction_id`.

### US-4: Preserve immediate cross-agent handoff causation (Priority: P2)

**As a** developer debugging agent-to-agent work, **I want** a new downstream trace to optionally record the parent trace that triggered it, **so that** I can inspect direct handoffs without inventing a workflow or discussion id.

**Independent test**: Have Alice tell idle Bob to do work and verify Bob's new trace contains `murmur.triggered_by_trace_id` pointing to Alice's trace.

## Acceptance Criteria

- [ ] Phoenix `session.id` is exported as the executing agent session id for agent, LLM, and tool spans.
- [ ] `murmur.agent_id` remains the concrete executing agent identity and is aligned with the Phoenix session grouping key.
- [ ] Each idle-to-active run creates exactly one new root trace identified by `murmur.request_id`.
- [ ] Steering or injected follow-up input delivered during an active run does not create a second root trace.
- [ ] Direct user messages to the same agent continue to appear under one Phoenix session row regardless of inactivity gap.
- [ ] Phoenix session grouping no longer depends on `ConversationCache` or `:conversation_session_timeout_ms`.
- [ ] `murmur.interaction_id` is removed from the canonical ingress contract, runtime tool context, delivery signals, and exported span attributes for this path.
- [ ] No new discussion, workflow, lineage, or replacement session-grouping id is introduced in place of `interaction_id`.
- [ ] Idle-started downstream work can still record immediate parent causation via `sender_trace_id` and `murmur.triggered_by_trace_id` when available.
- [ ] Architecture and observability documentation explain Phoenix sessions as agent-centric, traces as react-loop-centric, and parent-trace causation as optional immediate metadata only.
- [ ] Any now-obsolete direct-chat discussion cache and timeout behavior is removed or clearly deprecated from code and documentation.

## Scope

### In Scope

- Redefining Phoenix Sessions to be agent-centric
- Keeping one trace per executed react loop
- Removing `interaction_id` from canonical observability and ingress metadata for this path
- Removing `ConversationCache` and inactivity-timeout-based session rollover
- Preserving only immediate parent-trace causation for idle-started downstream work
- Updating architecture, observability, and package documentation to reflect the new model

### Out of Scope

- Introducing a new workflow, discussion, lineage, or replacement interaction id
- Reconstructing multi-hop workflow graphs as first-class Murmur runtime data
- Splitting one user message that contains several unrelated tasks into multiple independently tracked work items
- Reworking Phoenix UI screens outside the observability/session semantics needed for this change
- Redefining workspace or team correlation semantics beyond clarifying that they are separate from Phoenix session grouping