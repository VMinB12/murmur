# Plan: Runtime Metadata Boundary Cleanup

## Approach

Fix the current hop-depth propagation bug by making canonical ingress metadata the only source of truth for downstream runtime metadata, then remove the duplicated producer-side plumbing that currently rebuilds pieces of that metadata in multiple places.

The implementation will proceed in six layers:

1. Extend the canonical ingress metadata contract so hop depth and related workflow metadata are validated and available through one explicit access path.
2. Introduce a configurable hop-limit policy with a documented default, owned by Murmur configuration rather than a hardcoded runtime constant.
3. Change tell-limit exhaustion semantics so the calling agent receives an informative tool-visible outcome instead of a crash-shaped failure.
4. Introduce one explicit metadata projection boundary for runner-owned tool context and any runtime metadata that actions consume.
5. Centralize the repeated programmatic delivery pattern so producers no longer hand-roll the same PubSub signal plus ingress delivery flow, then align the remaining ingress-adjacent runtime data structures so one concept is represented by one primary structure instead of overlapping partial shapes.
6. Lock the behavior with focused tests and end-to-end chained inter-agent coverage, then update architecture docs to describe the simplified rule.

This keeps the ingress architecture from ticket 012 intact while cleaning up the remaining metadata inconsistency around that boundary.

Because Murmur has not yet published these packages, the plan should prefer cleaner structural alignment over preserving compatibility with transitional internal shapes. This ticket should remove legacy paths and fallback behavior in the affected runtime slice rather than preserving them behind shims.

## Key Design Decisions

### 1. Keep `refs` as the canonical Murmur-owned metadata envelope

Do not introduce a second top-level metadata contract beside canonical ingress input.

Rationale:

- matches ADR-003
- avoids splitting routing metadata across multiple runtime conventions
- keeps new workflow fields additive instead of architectural

### 2. Make hop-limit policy configurable with a documented default

Do not publish a fixed hop limit as an implicit package constant.

Rationale:

- routing policy should be part of the package surface, not an accidental hardcoded value
- package consumers may want different safety envelopes
- Murmur can keep a sensible default while avoiding a brittle permanent contract

### 3. Treat hop-limit exhaustion as informative tool feedback

When a tell exceeds the configured hop limit, the outcome should be surfaced back to the agent as a clear, tool-visible explanation instead of an opaque crash-shaped failure.

Rationale:

- the hop limit is a normal policy boundary, not an exceptional runtime fault
- agents can adapt if the failure is explicit and understandable
- this reduces brittle behavior in multi-agent workflows

### 4. Project runtime context from canonical ingress metadata exactly once

Add one explicit projection boundary that derives action-visible runtime context and related helper lookups from canonical ingress metadata.

Rationale:

- fixes the current hop-depth propagation hole at the root cause
- removes duplicated `ref_value` logic and partial context assembly
- gives Murmur one clear place to evolve runtime metadata semantics

### 5. Add a narrow shared helper for visible programmatic delivery

Centralize the repeated producer pattern that:

- emits a user-visible `MessageReceived` signal
- builds canonical programmatic ingress input
- delivers it through ingress

Rationale:

- removes duplicated metadata assembly in `TellAction`, task notifications, and similar follow-up paths
- reduces the chance that future producer paths drift in message shape or metadata fields

This helper should stay narrow and explicit so it does not become a new legacy-style catch-all wrapper.

### 6. Prefer aligned structures over compatibility fallbacks

Where ingress-adjacent runtime code currently represents one concept through multiple partially overlapping maps or helper conventions, converge on one structure and remove the others instead of adding compatibility readers.

Rationale:

- Murmur has not published this package surface yet
- the current moment is the cheapest time to remove transitional baggage
- fallback readers and compatibility branches would weaken the value of ADR-003 immediately

### 7. Preserve ticket 013 boundaries

Do not change Phoenix session grouping, `ConversationCache`, or discussion-versus-agent observability semantics in this ticket.

Rationale:

- that work already belongs to ticket 013
- metadata cleanup should remain focused on correctness and ingress-adjacent simplification

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Configurable hop policy drifts from the documented default or becomes hard to reason about | Medium | Medium | Keep one documented config key, one default, and explicit tests for default and override behavior |
| Informative hop-limit handling is implemented as another opaque error variant | Medium | Medium | Treat the limit as a normal tool-visible outcome and cover agent-facing behavior in tell tests and end-to-end chained workflows |
| Shared delivery helper becomes another over-general compatibility layer | Medium | Medium | Keep the helper scoped to visible programmatic follow-up delivery only and keep direct human delivery plus canonical `deliver_input/2` intact |
| Structure alignment accidentally expands into unrelated cleanup | Medium | Medium | Restrict alignment work to ingress-adjacent runtime concepts that changed under ADR-003 and are already covered by the ticket spec |
| Tool-context refactor breaks existing action behavior | Medium | High | Add focused tests for projected runtime context, especially `interaction_id`, `sender_name`, `sender_trace_id`, and `hop_count` |
| Hop-depth fix appears to pass unit tests but still fails across chained tells | Medium | High | Add end-to-end chained inter-agent tests rather than only local TellAction unit coverage |
| Producer migration changes UI-visible inbound message payload shape | Low | Medium | Preserve current `MessageReceived` payload semantics and cover them in task notification and tell-path tests |
| Work overlaps with ticket 013 and muddies observability semantics | Low | Medium | Limit this ticket to metadata projection and delivery consistency; defer session-grouping semantics to ticket 013 |