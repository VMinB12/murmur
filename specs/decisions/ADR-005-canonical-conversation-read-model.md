# ADR-005: Core-Owned Conversation Projector And UI Update Contract

**Status**: Accepted
**Date**: 2026-04-06
**Ticket**: `specs/tickets/016-conversation-read-model-and-streaming-consistency/`

## Context

Ticket 015 clarified actor identity and display projection for completed or refreshed conversation history, but it did not unify how Murmur renders in-progress turns while an agent run is still streaming.

Today Murmur has two separate conversation rendering paths:

- `WorkspaceLive` built an ad hoc per-session streaming map from `ai.*` signals and rendered it through `ChatStream`
- completed or refreshed history is loaded from thread state and projected through `UITurn` into canonical `DisplayMessage` values rendered by `ChatMessage`

That split creates two problems:

1. the live path is weaker than the completed path, so tool-call and thinking details can appear only after completion or refresh
2. stream signals and completion signals arrive on different PubSub topics, so the UI can mark a session idle and clear transient stream state before later valid `ai.llm.response` or `ai.tool.result` signals are handled

There is a second architectural gap underneath those problems: the UI does not currently receive one stable Murmur-owned conversation update contract with stable turn identity. `Runner` already creates a stable `request_id` for each run, but `WorkspaceLive` still reduces raw `ai.*` events directly by session-level state plus best-effort `call_id` handling.

The result is a UI that can temporarily hide state the system already knows, then "heal" after completion by reloading the richer thread-backed representation.

## Decision

Murmur should adopt one core-owned conversation projector and one Murmur-owned UI update contract for both live and persisted agent output.

Specifically:

- live stream facts and persisted thread entries should converge through one core-owned projector or equivalent reduction boundary rather than separate ad hoc UI models
- connected UIs should consume one Murmur-owned conversation snapshot or update contract instead of treating raw `ai.*` lifecycle signals as the rendering protocol
- every fact entering the projector must be associated with a stable turn identity, and tool lifecycle facts must preserve `tool_call_id` where available
- if upstream raw signals do not carry the required identity shape, Murmur should attach or derive it before reduction rather than forcing UI code to infer it from session-level heuristics
- the UI should render the same conceptual turn before, during, and after completion, with explicit lifecycle states for pending, running, completed, and finalized output
- helper APIs that load conversation state should consume the same canonical projector-backed boundary instead of duplicating live-versus-storage loading logic
- signal timing differences between stream and completion paths must not cause valid conversation state to be dropped silently

Raw `ai.*` signals may remain available for observability or other internal concerns, but Murmur should stop treating them as the public UI rendering contract. Finalized thread projection should reconcile through the same canonical projector-backed model instead of remaining a separate richer path.

## Consequences

Benefits:

- tool-call and thinking visibility become consistent across live rendering, completion, refresh, and reconnect
- timing races become easier to reason about because one core-owned projector owns state transitions
- package boundaries become clearer: `jido_murmur` owns conversation reduction, identity attachment, and UI-facing update contracts, while UI packages focus on rendering
- duplicated thread-loading and projection logic can be consolidated
- host apps gain one stable Murmur-owned rendering contract instead of an internal `ai.*` event stream

Trade-offs:

- this is a broader cleanup than a one-line fix to stale-signal handling
- some existing components, tests, and signal contracts will need to be rewritten around the new projector/update boundary
- Murmur must define and maintain explicit lifecycle semantics plus stable turn identity for in-progress turns rather than relying on implicit signal timing