# Tasks: Canonical Conversation Step Ordering

## Task List

Format: `- [ ] T001 [P] Description with file path`
- **T001, T002, …** — sequential task ID
- **[P]** — present only when the task can run in parallel with others
- Include the exact file path to create or modify in the description

### P1 — Canonical Assistant-Step Projection

- [x] T001 Move canonical tool-call value types out of `apps/jido_murmur/lib/jido_murmur/ui_turn.ex` into the canonical conversation namespace by updating `apps/jido_murmur/lib/jido_murmur/display_message.ex`, `apps/jido_murmur/lib/jido_murmur/conversation_read_model/turn.ex`, and any new canonical conversation modules they require, and cover the type ownership change in `apps/jido_murmur/test/jido_murmur/conversation_read_model_test.exs`.
- [x] T002 Replace request-level persisted grouping in `apps/jido_murmur/lib/jido_murmur/conversation_read_model.ex`, `apps/jido_murmur/lib/jido_murmur/conversation_projector.ex`, and `apps/jido_murmur/lib/jido_murmur/ui_turn.ex` with canonical assistant-step projection owned by `jido_murmur`, and lock reconnect/fresh-mount reconstruction in `apps/jido_murmur/test/jido_murmur/conversation_projector_test.exs`.
- [x] T003 Refactor live reduction in `apps/jido_murmur/lib/jido_murmur/conversation_read_model.ex` and `apps/jido_murmur/lib/jido_murmur/conversation_read_model/turn.ex` so one outer `request_id` can produce multiple assistant-step messages with Murmur-owned step ids and stable first-seen ordering, and cover multi-step request behavior in `apps/jido_murmur/test/jido_murmur/conversation_read_model_test.exs`.
- [x] T004 Align `apps/jido_murmur/lib/jido_murmur/conversation_projector.ex` and `apps/jido_murmur/lib/jido_murmur/streaming_plugin.ex` with the assistant-step model so canonical incremental updates stay Murmur-scoped and require no modifications under `deps/jido_ai/**`, and cover live step updates in `apps/jido_murmur/test/jido_murmur/conversation_projector_test.exs`.

### P1 — User And UI Ordering Paths

- [x] T005 Ensure visible programmatic user messages receive canonical first-seen metadata through `apps/jido_murmur/lib/jido_murmur/ingress/programmatic_delivery.ex`, and ensure optimistic local human messages preserve assistant-step ordering at the LiveView edge in `apps/murmur_demo/lib/murmur_web/live/workspace_live.ex` and `apps/murmur_demo/test/murmur_web/live/workspace_live_test.exs`.
- [x] T006 Remove ordering heuristics and compatibility paths from `apps/murmur_demo/lib/murmur_web/live/workspace_live.ex`, including `insert_user_message/3`, `find_last_running_assistant_index/1`, and any ordering-specific `upsert_message/2` behavior that becomes redundant once assistant-step ordering is present, and update `apps/murmur_demo/test/murmur_web/live/workspace_live_test.exs`.
- [x] T007 Replace any remaining message-id sorting or request-level rendering assumptions in `apps/murmur_demo/lib/murmur_web/live/workspace_state.ex`, `apps/murmur_demo/lib/murmur_web/components/workspace/unified_view.ex`, and `apps/murmur_demo/lib/murmur_web/components/workspace/split_view.ex` so both views render the same core-owned top-level message order, and cover cross-session interleaving in `apps/murmur_demo/test/murmur_web/live/workspace_live_integration_test.exs`.

### P1 — Legacy Removal, Docs, And Verification

- [x] T008 Delete `apps/jido_murmur/lib/jido_murmur/ui_turn.ex` and remove any remaining canonical read-path references to `UITurn` or `UITurn.ToolCall` from `apps/jido_murmur/lib/jido_murmur/display_message.ex`, `apps/jido_murmur/lib/jido_murmur/conversation_read_model.ex`, and related tests once the replacement projection path is in place.
- [x] T009 [P] Update `specs/Architecture/conversation-read-model.md`, `specs/Architecture/murmur-demo.md`, and `specs/Architecture/jido-murmur.md` to document that canonical ordering is assistant-step scoped, stays Murmur-owned, and removes the legacy `UITurn` read boundary in one pass.
- [x] T010 Run focused suites for `apps/jido_murmur/test/jido_murmur/conversation_read_model_test.exs`, `apps/jido_murmur/test/jido_murmur/conversation_projector_test.exs`, `apps/murmur_demo/test/murmur_web/live/workspace_live_test.exs`, `apps/murmur_demo/test/murmur_web/live/workspace_live_helpers_test.exs`, and `apps/murmur_demo/test/murmur_web/live/workspace_live_integration_test.exs`, then run `mix precommit` from `/Users/vincent.min/Projects/murmur`.

## Completion Criteria

All acceptance criteria from `Spec.md` are satisfied, canonical top-level message order is owned entirely by Murmur's read model, one outer request can project to multiple assistant-step messages, no `jido_ai` strategy or signal-contract changes are required, split and unified views render the same canonical order, and legacy ordering heuristics or compatibility shims are removed rather than preserved.