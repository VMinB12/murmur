# Spec: Canonical Conversation Step Ordering

## User Stories

### US-1: Stable assistant-step chronology across views (Priority: P1)

**As a** workspace user, **I want** split and unified chat views to show the same top-level conversation order, **so that** conversation flow does not change depending on the selected layout.

**Independent test**: Mount the same workspace in split and unified modes for a conversation containing user messages, assistant steps, and tool activity, and verify the rendered top-level messages appear in the same first-created order.

### US-2: Steering lands between assistant steps without local heuristics (Priority: P1)

**As a** workspace user, **I want** a human or `tell` message sent during an active assistant run to appear after the current assistant step and its tool outcomes but before the next assistant step, **so that** the visible order matches which phases of the run could still be influenced by that message.

**Independent test**: Send a human follow-up while a multi-step assistant run is active and verify the message appears after the current assistant step and before the next assistant step without relying on LiveView-local insertion logic.

### US-3: Reconnect-safe assistant-step reconstruction (Priority: P1)

**As a** Murmur maintainer, **I want** refresh, reconnect, and fresh-mount paths to preserve the same assistant-step sequence as the live connected view, **so that** canonical ordering survives snapshot and incremental update boundaries.

**Independent test**: Observe a live conversation with interleaved user messages and multiple assistant steps within one outer request, reconnect, and verify the reloaded snapshot renders the same top-level message order.

### US-4: Canonical read-model ownership without `UITurn` (Priority: P1)

**As a** Murmur maintainer, **I want** the canonical conversation read path to own persisted-entry projection and tool-call types directly, **so that** assistant-step ordering does not depend on a legacy request-level adapter.

**Independent test**: Inspect the canonical read-model entry points and verify persisted-entry projection and tool-call types no longer delegate through `UITurn` or `UITurn.ToolCall`.

## Acceptance Criteria

- [x] Canonical conversation state defines top-level message ordering by when each top-level message first entered canonical conversation state.
- [x] Assistant messages are segmented by assistant step rather than by whole outer request.
- [x] One assistant step corresponds to one LLM invocation plus the tool calls and tool results produced before the next LLM invocation or request completion.
- [x] A single outer `request_id` may produce multiple assistant-step messages.
- [x] Tool calls and tool results remain nested within the assistant step that produced them rather than becoming separately ordered top-level items.
- [x] Ordering does not rely on `request_id` as a universal sort key.
- [x] Ordering does not rely on `DisplayMessage.id` or persisted thread-entry ids as a proxy for creation time.
- [x] The implementation stays read-model scoped within Murmur's canonical conversation projector, read model, and persisted-entry projection boundary.
- [x] The implementation does not require `jido_ai` strategy, directive, or runtime contract changes.
- [x] Live read-model reduction no longer collapses all assistant lifecycle signals for one `request_id` into one canonical message.
- [x] Storage-backed projection no longer groups all assistant and tool entries by `request_id` alone.
- [x] The canonical conversation read path no longer depends on `UITurn` or `UITurn.ToolCall`.
- [x] Split and unified views both render the core-owned canonical top-level message order.
- [x] `WorkspaceLive` no longer needs view-local insertion heuristics to keep busy-session messages in the correct visible position.
- [x] Later updates to an existing assistant step do not change that step's original canonical order.
- [x] Refresh, reconnect, and fresh-mount paths preserve the same assistant-step sequence shown during live updates.
- [x] No transitional compatibility layer or legacy ordering path remains after the implementation ships.
- [x] If an existing ordering API or behavior conflicts with the canonical model, the implementation prefers the clean canonical model over backwards compatibility.
- [x] Regression tests cover at least one interrupted assistant-run scenario where a human or `tell` follow-up appears between assistant steps.
- [x] Regression tests cover at least one multi-step outer request with at least one tool-call cycle.
- [x] Regression tests cover at least one unified-view case with interleaved messages from more than one session.
- [x] Architecture documentation reflects the canonical assistant-step ordering rule and canonical read-path ownership if package boundaries or UI contracts change.

## Scope

### In Scope

- Defining the canonical rule for top-level conversation ordering
- Segmenting assistant messages by assistant step rather than by whole request
- Moving ordering and step-segmentation ownership to the core conversation projection boundary
- Replacing request-level persisted projection with canonical read-model-owned step projection
- Removing `UITurn` and `UITurn.ToolCall` instead of preserving transitional adapters
- Updating split and unified views to consume canonical order
- Removing ordering-specific view heuristics that become redundant
- Regression coverage for live, reconnect, multi-step, and interleaved ordering cases

### Out of Scope

- Redesigning the visual appearance of chat views
- Changing `jido_ai` strategy internals or signal contracts
- Ordering every visible sub-element independently as a top-level timeline item
- Reworking artifact rendering or task-board ordering
- Introducing thread branching or alternative conversation grouping models