# Plan: Conversation Read Model And Streaming Consistency

## Approach

Implement ticket 016 as a focused conversation-state cleanup rather than a narrow timing patch, so Murmur ends up with one package-owned read boundary for agent output instead of two separate rendering contracts.

1. Introduce one canonical conversation read model inside `jido_murmur` that can represent both in-progress and finalized turns. The model should cover the fields already needed by the UI today: actor/display metadata, assistant content, thinking content, tool calls, usage, and explicit lifecycle state for the assistant turn.
2. Add one shared reduction/projection boundary that can consume both persisted thread entries and live `ai.*` plus `murmur.message.completed` signals. Persisted refresh and live streaming should converge through this boundary instead of producing separate UI shapes.
3. Refactor `WorkspaceLive` so it stops owning the ad hoc `%{content, thinking, tool_calls, usage}` streaming map as an independent rendering model. The LiveView should maintain canonical conversation state per session, updating it from stream signals and reconciling it with completion without losing valid late-arriving data.
4. Consolidate duplicated conversation loading logic in `AgentHelper` and `WorkspaceState` behind the same package-owned API, so live-process reads, thawed-storage reads, and conversation projection are no longer duplicated across package and demo boundaries.
5. Keep the visual design broadly intact while unifying the underlying model. Shared and demo-owned components may continue to render in-progress and finalized turns differently if needed, but they should consume the same canonical conversation state instead of separate stream-versus-history contracts.
6. Add explicit race and equivalence regression coverage so the new boundary is locked in before any later PubSub or rendering changes.

This ticket should prefer structural clarity over local guard-condition fixes. If a small bug fix emerges along the way, it should land as part of the unified read-boundary work rather than as a competing stopgap path.

## Key Design Decisions

### 1. Make conversation read state a core-package concern

The canonical conversation read model should live in `jido_murmur`, not in `murmur_demo`.

Rationale:

- the split exists because the core package owns persisted thread semantics while the demo owns live stream assembly
- a package-owned read boundary is the only place that can legitimately unify live and persisted output for both host apps and helper APIs
- keeping read semantics in the core package preserves the boundary where `jido_murmur_web` and demo-owned UI code remain focused on rendering

### 2. Treat stream signals as incremental facts, not a separate UI protocol

`ai.llm.delta`, `ai.llm.response`, `ai.tool.started`, `ai.tool.result`, `ai.usage`, and `murmur.message.completed` should be reduced into the same turn state rather than stitched together into a special-purpose streaming map.

Rationale:

- this removes the conceptual split between `ChatStream` and `UITurn`-projected history
- state transitions become explicit and testable instead of being inferred from whichever signal happened to arrive first
- valid late signals can merge into the canonical turn state instead of being discarded because the UI already marked the session idle

### 3. Keep the current PubSub topology unless the reducer proves it insufficient

Do not begin by redesigning topic structure or collapsing stream and completion topics.

Instead, make the read-model layer tolerant of out-of-order delivery across the existing topics.

Rationale:

- the observed bug is real, but it does not yet prove that PubSub topology itself is wrong
- changing topology and read semantics at the same time would widen the blast radius unnecessarily
- an ordering-tolerant reducer is valuable even if topic structure changes later

### 4. Unify the model first, then simplify component boundaries

The first goal is a shared conversation state contract, not necessarily the immediate deletion of `ChatStream`.

However, after the shared model exists, component boundaries should be revisited and simplified if `ChatStream` and `ChatMessage` are found to differ only in presentation.

Rationale:

- this keeps the cleanup staged and reduces refactor risk
- it still leaves room to retire redundant rendering abstractions once the shared model is real
- it avoids mixing a structural read-model change with an avoidable UI rewrite in the same step

### 5. Build on ticket 015 rather than reopening it

Actor identity and display-message semantics from ticket 015 remain the foundation for this work.

The new read model should reuse those semantics and clarify how they behave during live turns, rather than introducing another competing identity or display abstraction.

Rationale:

- ticket 015 already established clearer actor/display ownership
- reopening those decisions would blur the scope of this follow-up
- the real missing piece is lifecycle and state reduction, not actor semantics

### 6. Consolidate thread hydration alongside read-model unification

Persisted thread normalization and projection should move into the same canonical read boundary instead of remaining partially embedded in `UITurn` and partially duplicated in helper/load functions.

Rationale:

- the same cleanup can remove duplicated live-versus-storage load logic in `AgentHelper` and `WorkspaceState`
- this addresses the earlier architectural concern that there is still no single conversation read boundary
- it creates a natural decision point for whether `UITurn` should be reduced, renamed, or absorbed after the canonical read model lands

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| The new reducer/read-model layer becomes too abstract and hard to adopt | Medium | Medium | Keep the initial API narrow: reduce live signals and persisted entries into the minimum state needed by current chat surfaces |
| Out-of-order signal handling remains flaky because identity keys are insufficient | Medium | High | Key state transitions by stable session/request/tool-call identifiers where available and add tests that intentionally reorder completion and tool signals |
| The refactor grows into a PubSub redesign instead of a read-model cleanup | Medium | Medium | Preserve current topics initially and only revisit topology if the canonical reducer cannot satisfy the acceptance criteria |
| UI components become temporarily more complex during migration | Medium | Medium | Migrate through a small adapter layer so `WorkspaceLive` can adopt the shared model before fully simplifying shared components |
| Persisted thread entries and live signal payloads prove mismatched in detail | Medium | Medium | Let finalized thread-backed state reconcile and overwrite incomplete transient details while preserving the same conceptual turn identity |
| Host-package boundaries become muddled between `jido_murmur`, `jido_murmur_web`, and `murmur_demo` | Low | Medium | Keep state reduction/projection in `jido_murmur`, rendering primitives in `jido_murmur_web`, and screen-specific orchestration in `murmur_demo` |