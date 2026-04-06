# Plan: Conversation Read Model And Streaming Consistency

## Approach

Implement ticket 016 as a focused conversation-state cleanup rather than a narrow timing patch, so Murmur ends up with one core-owned conversation projector and one Murmur-owned UI update contract instead of two separate rendering contracts.

1. Introduce one canonical conversation model and projector inside `jido_murmur` that can represent both in-progress and finalized turns. The model should cover the fields already needed by the UI today: actor/display metadata, assistant content, thinking content, tool calls, usage, explicit lifecycle state, and stable turn identity for the assistant turn.
2. Feed that projector from both persisted thread entries and live `ai.*` plus `murmur.message.completed` facts. If upstream raw signals do not carry a stable turn identifier, Murmur should attach or derive one at the ingestion boundary before reducing them.
3. Expose one Murmur-owned conversation snapshot or update contract for UI consumers. `WorkspaceLive` should stop reducing raw `ai.*` signals into a private rendering map and instead mount from projector-backed snapshots, then consume projector-driven `murmur.*` turn updates while connected.
4. Consolidate duplicated conversation loading logic in `AgentHelper` and `WorkspaceState` behind the same projector-backed API, so live-process reads, thawed-storage reads, and conversation projection are no longer duplicated across package and demo boundaries.
5. Keep the visual design broadly intact while unifying the underlying model. Shared and demo-owned components may continue to render in-progress and finalized turns differently if needed, but they should consume the same canonical conversation state, and redundant abstractions such as `ChatStream` or `UITurn` should be reduced or absorbed when the shared model makes them unnecessary.
6. Add explicit race, reconnect, and equivalence regression coverage so the new boundary is locked in before any later PubSub or rendering changes.

This ticket should prefer structural clarity over local guard-condition fixes. Because backward compatibility is not a constraint here, Murmur should favor the cleanest ownership model even if it means replacing the current UI-facing stream contract rather than wrapping it.

## Key Design Decisions

### 1. Make conversation read state a core-package concern

The canonical conversation projector and read model should live in `jido_murmur`, not in `murmur_demo`.

Rationale:

- the split exists because the core package owns persisted thread semantics while the demo owns live stream assembly
- a core-owned projector is the only place that can legitimately unify live and persisted output for both host apps and helper APIs
- keeping read semantics in the core package preserves the boundary where `jido_murmur_web` and demo-owned UI code remain focused on rendering

### 2. Treat stream signals as incremental facts, not a separate UI protocol

`ai.llm.delta`, `ai.llm.response`, `ai.tool.started`, `ai.tool.result`, `ai.usage`, and `murmur.message.completed` should be reduced into the same turn state rather than stitched together into a special-purpose streaming map.

Rationale:

- this removes the conceptual split between `ChatStream` and `UITurn`-projected history
- state transitions become explicit and testable instead of being inferred from whichever signal happened to arrive first
- valid late signals can merge into the canonical turn state instead of being discarded because the UI already marked the session idle

### 3. Introduce one Murmur-owned UI update contract

Connected UIs should consume one Murmur-owned conversation snapshot or update contract rather than treating raw `ai.*` signals as the rendering protocol.

Raw `ai.*` signals may continue to exist for observability or internal orchestration, but they should no longer be the public UI-facing contract for chat rendering.

The expected transport shape is:

- full snapshot on mount or reconnect
- incremental canonical turn updates while connected

It is intentionally not a full conversation snapshot on every token.

Rationale:

- this gives host apps one stable rendering boundary owned by Murmur instead of a thinly wrapped internal lifecycle stream
- it keeps LiveViews and components focused on presentation instead of reduction logic
- it prevents future UI divergence when another host app or reconnect path consumes conversation state differently

### 4. Require stable turn identity at the projector boundary

Every fact entering the canonical projector must be associated with a stable turn identity, and tool lifecycle events must carry or preserve `tool_call_id` where available.

If upstream raw signals do not provide the right identity shape, Murmur should attach or derive it before reduction rather than forcing UI code to infer it from `session_id` and `call_id` heuristics.

Rationale:

- out-of-order reconciliation is only reliable when the reducer can associate late facts with the right turn
- `request_id` already exists in Murmur's runtime and is the right kind of stable run-level identity to build on
- this is the cleanest way to eliminate the current session-level ambiguity in `WorkspaceLive`

### 5. Keep the current PubSub topology unless the projector proves it insufficient

Do not begin by redesigning topic structure or collapsing stream and completion topics.

Instead, make the projector and UI-facing contract tolerant of out-of-order delivery across the existing topics.

Rationale:

- the observed bug is real, but it does not yet prove that PubSub topology itself is wrong
- changing topology and read semantics at the same time would widen the blast radius unnecessarily
- an ordering-tolerant projector is valuable even if topic structure changes later

### 6. Unify the model first, then simplify component boundaries

The first goal is a shared conversation state contract, not necessarily the immediate deletion of `ChatStream`.

However, after the shared model exists, component boundaries should be revisited and simplified if `ChatStream` and `ChatMessage` are found to differ only in presentation.

Rationale:

- this keeps the cleanup staged and reduces refactor risk
- it still leaves room to retire redundant rendering abstractions once the shared model is real
- because backward compatibility is not required, redundant abstractions should actually be retired during this ticket if the shared model makes them unnecessary

### 7. Build on ticket 015 rather than reopening it

Actor identity and display-message semantics from ticket 015 remain the foundation for this work.

The new read model should reuse those semantics and clarify how they behave during live turns, rather than introducing another competing identity or display abstraction.

Rationale:

- ticket 015 already established clearer actor/display ownership
- reopening those decisions would blur the scope of this follow-up
- the real missing piece is lifecycle and state reduction, not actor semantics

### 8. Treat finalized thread projection as reconciliation, not a separate rendering path

When finalized thread state is available, it should reconcile with or overwrite incomplete in-progress projector state through the same canonical conversation model instead of becoming a second rendering path.

Rationale:

- this is what turns refresh, reconnect, and completion into the same conceptual output instead of a UI "healing" step
- it gives Murmur one answer to the question of what the current visible turn state is
- it prevents the persisted path from remaining secretly richer than the live path after the main refactor

### 9. Consolidate thread hydration alongside read-model unification

Persisted thread normalization and projection should move into the same canonical read boundary instead of remaining partially embedded in `UITurn` and partially duplicated in helper/load functions.

Rationale:

- the same cleanup can remove duplicated live-versus-storage load logic in `AgentHelper` and `WorkspaceState`
- this addresses the earlier architectural concern that there is still no single conversation read boundary
- it creates a natural decision point for whether `UITurn` should be reduced, renamed, or absorbed after the canonical read model lands

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| The new projector/read-model layer becomes too abstract and hard to adopt | Medium | Medium | Keep the initial API narrow: reduce live signals and persisted entries into the minimum state needed by current chat surfaces |
| Out-of-order signal handling remains flaky because identity keys are insufficient | Medium | High | Require stable turn identity at the projector boundary, preserve `tool_call_id`, and add tests that intentionally reorder completion and tool signals |
| The refactor grows into a PubSub redesign instead of a read-model cleanup | Medium | Medium | Preserve current topics initially and only revisit topology if the canonical projector cannot satisfy the acceptance criteria |
| UI components become temporarily more complex during migration | Medium | Medium | Migrate UIs to the Murmur-owned update contract first, then retire redundant rendering abstractions in the same ticket |
| Persisted thread entries and live signal payloads prove mismatched in detail | Medium | Medium | Let finalized thread-backed state reconcile and overwrite incomplete in-progress state through the same canonical model |
| Host-package boundaries become muddled between `jido_murmur`, `jido_murmur_web`, and `murmur_demo` | Low | Medium | Keep projector state and update contracts in `jido_murmur`, rendering primitives in `jido_murmur_web`, and screen-specific orchestration in `murmur_demo` |