# ADR-002: Single Ingress Coordinator Actor

**Status**: Accepted
**Date**: 2026-04-04
**Ticket**: `specs/tickets/012-native-react-steering-adoption/`

## Context

Murmur historically used a session-level follow-up buffering path plus `MessageInjector` request transformer to solve both:

- idle-agent ingress
- busy-agent mid-run follow-up delivery

`jido_ai` 2.1 now provides native `steer/3` and `inject/3` for active ReAct runs. That removes the need for Murmur to emulate busy-agent follow-up delivery inside a request transformer.

What remains unsolved by upstream is the delivery protocol boundary: when a new input arrives, who decides whether it should become a fresh `ask`, a `steer`, or an `inject` call?

If each caller makes that decision independently, stale state races remain possible outside the agent actor boundary.

## Decision

Murmur will introduce a single ingress coordinator actor per agent session.

The coordinator is the only Murmur-owned process allowed to decide whether inbound input should:

- start a fresh `ask/await` run
- be routed into the active run with `steer/3`
- be routed into the active run with `inject/3`

The canonical ingress data contract will be aligned to `jido_ai` control payloads:

- `content`
- `source`
- `refs`
- optional `expected_request_id`

Murmur-specific metadata such as `interaction_id`, `sender_name`, `sender_trace_id`, and workspace causation will live inside `refs`.

Request transformers remain in place only for Murmur-owned context shaping, such as team instructions and SQL schema enrichment. They are no longer the primary delivery mechanism for busy-agent follow-up input.

## Consequences

Benefits:

- Murmur stops owning a custom mid-run message delivery workaround that upstream now provides natively.
- The actor model is applied at the right boundary: one actor owns the delivery protocol for each session.
- Ask-versus-steer routing is no longer duplicated across callers.
- The data model moves closer to `jido_ai`, reducing long-term translation and maintenance cost.

Trade-offs:

- Murmur gains a new coordinator component in its supervision tree.
- Run-boundary retry behavior must now be implemented explicitly inside the coordinator.
- Existing delivery-path tests and documentation must be rewritten around the new coordinator semantics.