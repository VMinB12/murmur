# ADR-003: Runtime Metadata Projection Boundary

**Status**: Accepted
**Date**: 2026-04-05
**Ticket**: `specs/tickets/014-runtime-metadata-boundary-cleanup/`

## Context

Ticket 012 established a clean ingress boundary around canonical input shaped as:

- `content`
- `source`
- `refs`
- optional `expected_request_id`

That made delivery routing much cleaner, but it also exposed a second boundary that is still too implicit: how Murmur projects runtime metadata from canonical ingress input into the context visible to tools, observability, and downstream producers.

Today that metadata is partially carried in `refs`, partially reprojected into runner-owned tool context maps, and partially reassembled by downstream callers. That overlap creates two problems:

1. correctness bugs are easier to introduce because metadata must be propagated through more than one path
2. new fields such as hop depth, causation, or trace linkage require repeated plumbing across ingress, runner, and action code

The current hop-depth bug in inter-agent delivery is an example of this failure mode: `TellAction` validates and increments `hop_count`, but the runtime does not treat it as part of one explicit projection contract all the way into the next action context.

## Decision

Murmur will treat canonical ingress metadata as the single source of truth for runtime delivery metadata.

Specifically:

- `refs` remains the canonical Murmur-owned metadata envelope on ingress input
- action-visible runtime context must be projected from canonical ingress metadata through one explicit projection boundary
- runner-owned tool context, observability correlation, and downstream action context must not each invent or selectively reconstruct their own metadata shape
- metadata that affects routing, safety, or workflow semantics, such as `interaction_id`, `sender_name`, `sender_trace_id`, `hop_count`, and future causation fields, must be added through the canonical ingress path first and then projected consistently

This decision does not require one specific module name, but implementation should converge on one clear projection point rather than continuing to duplicate ref lookup and ad hoc context assembly in multiple modules.

Programmatic delivery helpers may still build user-visible PubSub signals where needed, but the runtime metadata they attach must come from the same canonical ingress contract.

## Consequences

Benefits:

- metadata propagation bugs become easier to detect because there is one contract and one projection boundary
- inter-agent safety controls such as hop depth become more reliable
- runner, actions, and observability can evolve without each carrying their own partial metadata conventions
- adding new workflow metadata becomes cheaper because it no longer requires repeated bespoke plumbing

Trade-offs:

- Murmur needs an additional layer of explicitness around metadata projection instead of relying on loose maps
- some current helpers and duplicated ref lookup code will need to be consolidated
- a small follow-up refactor is required to align existing producers and tool context assembly with this decision