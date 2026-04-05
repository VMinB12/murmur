# ADR-006: Agent-Centric Phoenix Sessions And Immediate Trace Causation

**Status**: Accepted
**Date**: 2026-04-05
**Ticket**: `specs/tickets/013-agent-centric-phoenix-sessions/`

## Context

Murmur's current observability model treats `interaction_id` as a discussion or workflow identifier and copies it into Phoenix `session.id`.

For direct human chat, that model relies on `ConversationCache` and an inactivity timeout to decide when one discussion ends and another begins. For agent-to-agent work, it propagates a shared `interaction_id` so traces from multiple agents appear under one Phoenix session row.

That model no longer matches how Murmur is expected to work:

- users may return to the same agent after a long gap and continue meaningful work
- one agent may receive several unrelated human requests over time
- a single active react loop may absorb several direct follow-up messages and several inter-agent tells
- once multiple upstream messages influence one loop, a single scalar workflow or lineage identifier is not well defined

The product has two stable concepts only:

- one concrete agent session
- one executed react loop

Any additional correlation should therefore stay minimal and local.

## Decision

Murmur should simplify its observability model as follows:

- Phoenix `session.id` represents the concrete executing agent session id.
- Each executed react loop remains its own root trace and is identified by `murmur.request_id`.
- `interaction_id` is removed from the canonical ingress and observability model instead of being renamed or redefined.
- `ConversationCache` and inactivity-timeout-based session rollover are removed because they exist only to support the discarded discussion model.
- Murmur keeps only immediate parent-trace causation for new downstream idle-agent runs through `sender_trace_id` on delivery and `murmur.triggered_by_trace_id` on exported traces.
- Murmur does not introduce a replacement workflow, discussion, or lineage identifier in this ticket.

## Consequences

Benefits:

- Phoenix Sessions now has one stable meaning: all traces for one agent
- trace boundaries remain aligned to real runtime execution rather than message count
- the runtime no longer needs heuristics to infer when a discussion starts or ends
- the observability model becomes easier to explain: session = agent, trace = loop, parent trace = direct cause

Trade-offs:

- Murmur gives up easy scalar grouping of multi-agent workflows across several agents
- developers must rely on `murmur.workspace_id` and immediate parent-trace causation rather than a shared interaction id
- ingress contracts, tests, and docs that currently require `interaction_id` must be updated together