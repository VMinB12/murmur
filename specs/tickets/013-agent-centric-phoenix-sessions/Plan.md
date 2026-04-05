# Plan: Agent-Centric Phoenix Sessions

## Approach

Implement ticket 013 as a focused simplification of Murmur's observability model.

The implementation should proceed in five layers:

1. Re-anchor Phoenix session grouping on the concrete agent session id so `session.id` and `murmur.agent_id` describe the same runtime identity.
2. Preserve the current root-trace boundary of one trace per executed react loop by keeping new traces tied to idle-to-active transitions and keeping busy-run follow-up input inside the active trace.
3. Remove `interaction_id` from the canonical ingress, runtime metadata, and exported span model instead of renaming or redefining it.
4. Delete `ConversationCache` and any inactivity-timeout-based session rollover wiring so no inferred discussion lifecycle remains in the runtime.
5. Preserve only immediate handoff causation by carrying `sender_trace_id` through delivery and exporting `murmur.triggered_by_trace_id` when one trace starts a new downstream idle-agent run.

This ticket should prefer deletion over compatibility shims. Murmur has not yet published this package surface, and the simplest durable model is worth the cleanup cost now.

This plan includes an architecture decision record and project-level observability documentation updates because the ticket changes the documented meaning of Phoenix sessions and removes a previously documented correlation concept.

## Key Design Decisions

### 1. Export Phoenix `session.id` as the concrete agent session id

Phoenix Sessions should answer one question only: which agent produced this work?

Rationale:

- matches the stable product concept Murmur actually has
- keeps long-lived per-agent history visible even across long inactivity gaps
- removes the need for heuristics to infer when a conversation starts or ends

### 2. Keep root traces aligned to executed react loops

Do not start a new root trace for every inbound message.

Rationale:

- a busy agent can absorb multiple follow-up inputs inside one active run
- creating one trace per inbound message would duplicate one real loop across several traces
- the current ingress coordinator already has the right execution boundary semantics

### 3. Remove `interaction_id` entirely instead of redefining it

Do not replace discussion semantics with a renamed scalar such as `lineage_id`.

Rationale:

- one react loop can be influenced by several human messages and tells, so a single scalar lineage identifier is not well defined
- redefining the field would preserve ambiguity rather than remove it
- immediate parent causation is useful; synthetic workflow identity is not required for this ticket

### 4. Keep only immediate parent-trace causation

Preserve optional direct handoff metadata through `sender_trace_id` on delivery and `murmur.triggered_by_trace_id` on newly started downstream traces.

Rationale:

- gives real debugging value for idle agent handoffs
- keeps the mental model simple: session = agent, trace = loop, parent trace = direct cause
- avoids turning Murmur into a workflow-graph system before it needs one

### 5. Remove the discussion cache completely

Delete `ConversationCache` and the timeout-based rollover behavior instead of keeping it dormant.

Rationale:

- the cache exists only to support a session concept the team no longer wants
- leaving it around would keep cleanup hooks, tables, and tests misleadingly alive
- removal is simpler than deprecation inside an unpublished package surface

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Removing `interaction_id` breaks ingress callers or tests that still assume it is required | High | High | Update ingress builders, metadata validation, delivery signals, and focused tests together in one slice of work |
| Developers lose convenient cross-agent grouping that previously came from a shared interaction id | Medium | Medium | Preserve `murmur.workspace_id` and immediate `murmur.triggered_by_trace_id`, and document the simpler model explicitly |
| Stale `ConversationCache` cleanup hooks or ETS wiring remain after the refactor | Medium | Medium | Remove cache references from runtime cleanup paths and cover the removal in focused runtime tests |
| Busy-run follow-up input accidentally starts duplicate root traces during the refactor | Medium | High | Keep the coordinator-owned delivery model intact and add integration coverage for active-run `steer` and `inject` behavior |