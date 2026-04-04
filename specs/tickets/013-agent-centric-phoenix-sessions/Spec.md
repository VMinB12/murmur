# Spec: Agent-Centric Phoenix Sessions

## User Stories

### US-1: One Phoenix session row per agent (Priority: P1)

**As a** developer inspecting Murmur activity in Arize Phoenix, **I want** Phoenix Sessions to show one stable row per agent session, **so that** all work performed by a given agent is grouped under that agent regardless of pauses between messages.

**Independent test**: Send multiple direct messages to the same agent over a long time gap and verify all resulting traces remain grouped under one Phoenix session row keyed by that agent.

### US-2: Preserve workflow correlation without using Phoenix session grouping (Priority: P1)

**As a** developer debugging multi-agent workflows, **I want** cross-agent relationships to remain visible through Murmur correlation metadata, **so that** agent-centric Phoenix Sessions does not erase my ability to trace one workflow across multiple agents.

**Independent test**: Run an Alice-to-Bob workflow and verify Alice and Bob still export a shared workflow correlation field even though their Phoenix `session.id` values differ by agent.

### US-3: Remove heuristic discussion rollover from session grouping (Priority: P1)

**As a** Murmur maintainer, **I want** Phoenix session grouping to stop depending on an inactivity timeout or inferred direct-chat discussion cache, **so that** the grouping model matches a stable product concept instead of a runtime heuristic.

**Independent test**: Inspect the runtime behavior for direct messages and verify Phoenix `session.id` no longer changes because of elapsed inactivity time.

### US-4: Keep separate semantics for agent identity and workflow identity (Priority: P2)

**As a** developer reading observability data, **I want** the exported fields to make it clear which id represents the concrete agent and which id represents cross-agent workflow correlation, **so that** agent-centric grouping does not blur causal relationships.

**Independent test**: Inspect one direct turn and one cross-agent turn and verify `session.id` matches the executing agent identity while `murmur.interaction_id` continues to represent workflow or message-level correlation when available.

## Acceptance Criteria

- [ ] Phoenix `session.id` is exported as the executing agent session id for agent, LLM, and tool spans.
- [ ] Direct user messages to the same agent continue to group under the same Phoenix session row even after long inactivity periods.
- [ ] Direct-message session grouping no longer depends on `ConversationCache` or `:conversation_session_timeout_ms`.
- [ ] Cross-agent workflows no longer rely on Phoenix Sessions to appear as one grouped session row across agents.
- [ ] `murmur.interaction_id` remains available as the cross-agent workflow or message correlation key when present.
- [ ] `murmur.agent_id` remains the concrete executing agent identity and is aligned with the Phoenix session grouping key.
- [ ] Architecture and observability documentation explain the new product meaning of Phoenix Sessions as an agent-centric view rather than a discussion-centric view.
- [ ] Any now-obsolete direct-chat discussion cache or timeout behavior is removed or clearly deprecated from code and documentation.

## Scope

### In Scope

- Redefining Phoenix Sessions to be agent-centric
- Updating observability export semantics for `session.id`
- Removing or deprecating `ConversationCache` and inactivity-timeout-based session grouping
- Preserving cross-agent workflow correlation through Murmur-specific metadata
- Updating architecture and observability documentation to reflect the new model

### Out of Scope

- Introducing a first-class persisted discussion or thread id model
- Changing the root trace boundary model of one trace per executed react loop
- Reworking Phoenix UI screens outside the observability/session semantics needed for this change
- Redefining workspace or team correlation semantics beyond clarifying that they are separate from Phoenix session grouping