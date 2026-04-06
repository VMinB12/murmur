# Plan: Canonical Conversation Step Ordering

## Approach

Implement canonical top-level message ordering entirely inside Murmur's conversation read boundary, with assistant messages segmented by assistant step rather than by whole outer request.

The implementation should introduce one explicit first-seen ordering key for canonical top-level messages and assign it when a message first enters canonical state. That key should then be preserved across later content updates, snapshot reloads, and reconnects.

The implementation should use existing upstream data rather than changing `jido_ai` strategy behavior:

- persisted thread entries already carry ordered `seq` values, `at` timestamps, and request-related refs through Jido thread normalization and Murmur storage
- live assistant lifecycle signals already pass through Murmur's `StreamingPlugin` and `ConversationProjector` before the UI sees them

The intended end state is:

- `jido_murmur` owns assistant-step segmentation, ordering metadata, and sorting
- one outer request may produce several canonical assistant-step messages
- `WorkspaceLive` and `WorkspaceState` consume canonical ordered messages directly
- `UITurn` is removed from the canonical read path rather than preserved behind a compatibility layer
- legacy ordering heuristics are removed rather than preserved behind a compatibility layer

## Key Design Decisions

### 1. Make assistant step the canonical assistant message

Do not define canonical assistant messages at the outer `request_id` boundary.

Instead:

- a human or `tell` message remains one top-level user message
- an assistant step becomes one top-level assistant message
- that assistant step contains the text, thinking, tool calls, and tool results produced by one LLM invocation before the next LLM invocation or request completion

This is the smallest model that matches the desired steering semantics without turning every visible sub-element into its own timeline item.

### 2. Keep the change Murmur-scoped

Do not change `jido_ai` strategies, directives, or signal contracts.

Step segmentation and ordering should be derived from data Murmur already receives:

- persisted entries in append-only sequence order
- live lifecycle signals with request/run metadata already attached by upstream emitters
- deterministic Murmur-owned tie-breakers when timestamps are equal

This keeps the implementation inside the projector and read model instead of spreading it into the runtime loop.

### 3. Use Murmur-owned step identity and explicit ordering metadata

Do not rely on `request_id`, `DisplayMessage.id`, or thread-entry ids as a proxy for chronology or assistant-message identity.

Instead:

- keep `request_id` as outer run identity
- assign each assistant step a Murmur-owned stable step id
- assign explicit first-seen ordering metadata when the top-level message first enters canonical state
- preserve both identity and ordering metadata across later updates

### 4. Replace the legacy persisted projection in the same pass

The implementation should remove `UITurn` and `UITurn.ToolCall` while assistant-step projection lands.

Keeping request-level grouping in `UITurn` while live projection moves to assistant steps would force either:

- a transitional compatibility adapter, or
- two different canonical projection rules for live and refreshed state

The cleaner end state is to move persisted-entry projection and tool-call types into the canonical conversation namespace immediately.

### 5. Remove legacy ordering paths in one pass

The implementation should delete the current ordering heuristics once canonical ordering is in place:

- `WorkspaceLive` insertion logic for busy-session user messages
- `WorkspaceLive` position-preserving replacement assumptions that only exist to compensate for missing order metadata
- request-level collapsing in the live read model
- request-level persisted grouping through `UITurn`

If any internal helper or rendering path becomes incompatible, prefer the cleaner canonical boundary over backwards-compatible shims.

### 6. Use one rule for both split and unified views

The split view and unified view should both render the same canonical top-level message order. The unified timeline may still merge per-session messages into one list, but it should do so by the canonical first-seen key rather than by message id.

## Risks & Mitigations

### Risk: live and persisted step segmentation diverge

If live reduction and persisted projection infer assistant-step boundaries differently, reconnects could reorder messages or reshape tool-call nesting.

Mitigation:

- use one canonical step-projection rule for both live and persisted paths
- base the persisted projection on append-only entry sequence rather than on request-level grouping
- add mirrored regressions that compare live updates and snapshot reloads for the same multi-step run

### Risk: the live read model routes an event to the wrong assistant step

Tool and usage events arrive after an assistant step has already been created, and later LLM activity for the same outer request must open a new step instead of mutating the old one.

Mitigation:

- keep explicit per-request step state in the read model
- use tool-call ids and existing request/run metadata as correlation hints
- treat upstream `iteration` metadata as useful evidence when present, but do not make correctness depend on modifying `jido_ai`

### Risk: cleanup breadth increases the implementation surface

Assistant-step ordering now overlaps with canonical projection cleanup, UI heuristics, and persisted reconstruction.

Mitigation:

- land the read-boundary rewrite in one pass under ticket 017
- archive ticket 018 as superseded rather than keeping a second implementation ticket alive
- validate the rewrite through focused projector, read-model, and LiveView regressions before running `mix precommit`