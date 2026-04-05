# ADR-005: Canonical Conversation Read Model For Live And Persisted Output

**Status**: Proposed
**Date**: 2026-04-05
**Ticket**: `specs/tickets/016-conversation-read-model-and-streaming-consistency/`

## Context

Ticket 015 clarified actor identity and display projection for completed or refreshed conversation history, but it did not unify how Murmur renders in-progress turns while an agent run is still streaming.

Today Murmur has two separate conversation rendering paths:

- `WorkspaceLive` builds an ad hoc per-session streaming map from `ai.*` signals and renders it through `ChatStream`
- completed or refreshed history is loaded from thread state and projected through `UITurn` into canonical `DisplayMessage` values rendered by `ChatMessage`

That split creates two problems:

1. the live path is weaker than the completed path, so tool-call and thinking details can appear only after completion or refresh
2. stream signals and completion signals arrive on different PubSub topics, so the UI can mark a session idle and clear transient stream state before later valid `ai.llm.response` or `ai.tool.result` signals are handled

The result is a UI that can temporarily hide state the system already knows, then "heal" after completion by reloading the richer thread-backed representation.

## Decision

Murmur should adopt one canonical conversation read model for both live and persisted agent output.

Specifically:

- live stream signals and persisted thread entries should converge through one package-owned reduction/projection boundary rather than separate ad hoc UI models
- the UI should render the same conceptual turn before, during, and after completion, with explicit lifecycle states for pending, running, completed, and finalized output
- helper APIs that load conversation state should consume the same canonical read boundary instead of duplicating live-versus-storage loading logic
- signal timing differences between stream and completion paths must not cause valid conversation state to be dropped silently

The exact implementation may use a reducer, projector, or equivalent read-model API, but Murmur should stop treating live stream state and completed conversation history as different rendering contracts.

## Consequences

Benefits:

- tool-call and thinking visibility become consistent across live rendering, completion, and refresh
- timing races become easier to reason about because one model owns state transitions
- package boundaries become clearer: `jido_murmur` owns conversation reduction/projection, while UI packages focus on rendering
- duplicated thread-loading and projection logic can be consolidated

Trade-offs:

- this is a broader cleanup than a one-line fix to stale-signal handling
- some existing components and tests will need to be rewritten around the new read boundary
- Murmur must define and maintain explicit lifecycle semantics for in-progress turns rather than relying on implicit signal timing