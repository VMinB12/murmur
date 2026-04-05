# Tasks: Conversation Read Model And Streaming Consistency

## Task List

Format: `- [ ] T001 [P] Description with file path`
- **T001, T002, …** — sequential task ID
- **[P]** — present only when the task can run in parallel with others
- Include the exact file path to create or modify in the description

### P1 — Canonical Conversation Read Boundary

- [ ] T001 Create the canonical conversation read-model structs and reducer in `apps/jido_murmur/lib/jido_murmur/conversation_read_model.ex` and `apps/jido_murmur/lib/jido_murmur/conversation_read_model/turn.ex`, covering persisted and live turn lifecycle reduction in `apps/jido_murmur/test/jido_murmur/conversation_read_model_test.exs`.
- [ ] T002 Refactor `apps/jido_murmur/lib/jido_murmur/ui_turn.ex` and `apps/jido_murmur/lib/jido_murmur/display_message.ex` so persisted thread projection flows through the canonical conversation read boundary instead of a standalone projection path, and update `apps/jido_murmur/test/jido_murmur/ui_turn_test.exs`.
- [ ] T003 Extend the canonical conversation reducer to consume live `ai.llm.delta`, `ai.llm.response`, `ai.tool.started`, `ai.tool.result`, `ai.usage`, and `murmur.message.completed` signals in `apps/jido_murmur/lib/jido_murmur/conversation_read_model.ex`, locking explicit lifecycle and out-of-order reconciliation behavior in `apps/jido_murmur/test/jido_murmur/conversation_read_model_test.exs`.

### P2 — LiveView And Helper Integration

- [ ] T004 Replace the ad hoc `%{content, thinking, tool_calls, usage}` streaming state in `apps/murmur_demo/lib/murmur_web/live/workspace_live.ex` with canonical conversation-state updates from the shared read boundary, including late-signal reconciliation after completion, and cover it in `apps/murmur_demo/test/murmur_web/live/workspace_live_test.exs`.
- [ ] T005 Consolidate duplicated live-versus-storage conversation loading in `apps/jido_murmur/lib/jido_murmur/agent_helper.ex` and `apps/murmur_demo/lib/murmur_web/live/workspace_state.ex` behind the canonical read API, updating `apps/jido_murmur/test/jido_murmur/agent_helper_test.exs` and `apps/murmur_demo/test/murmur_web/live/workspace_live_helpers_test.exs`.
- [ ] T006 Adapt `apps/jido_murmur_web/lib/jido_murmur_web/components/chat_stream.ex`, `apps/jido_murmur_web/lib/jido_murmur_web/components/chat_message.ex`, `apps/murmur_demo/lib/murmur_web/components/workspace/split_view.ex`, and `apps/murmur_demo/lib/murmur_web/components/workspace/unified_view.ex` to render canonical in-progress and finalized turn state consistently, and update `apps/jido_murmur_web/test/jido_murmur_web/components/chat_test.exs` plus `apps/murmur_demo/test/murmur_web/live/workspace_live_integration_test.exs`.

### P3 — Regression Coverage And Docs

- [ ] T007 Add regression coverage for out-of-order completion and tool-call visibility in `apps/murmur_demo/test/murmur_web/live/workspace_live_test.exs` and `apps/murmur_demo/test/murmur_web/live/workspace_live_reconnect_test.exs`, including a case where `murmur.message.completed` arrives before later `ai.llm.response` or `ai.tool.result` signals.
- [ ] T008 [P] Update `specs/Architecture/jido-murmur.md`, `specs/Architecture/jido-murmur-web.md`, and `specs/Architecture/murmur-demo.md` to document the canonical conversation read boundary and live-versus-persisted convergence, and update `specs/decisions/ADR-005-canonical-conversation-read-model.md` if the implemented shape confirms the proposed decision.
- [ ] T009 Run focused suites for `apps/jido_murmur/test/jido_murmur/conversation_read_model_test.exs`, `apps/jido_murmur/test/jido_murmur/ui_turn_test.exs`, `apps/jido_murmur_web/test/jido_murmur_web/components/chat_test.exs`, `apps/murmur_demo/test/murmur_web/live/workspace_live_test.exs`, and `apps/murmur_demo/test/murmur_web/live/workspace_live_integration_test.exs`, then run `mix precommit` from `/Users/vincent.min/Projects/murmur`.

## Completion Criteria

All acceptance criteria from `Spec.md` are satisfied, live and refreshed chat rendering consume one canonical conversation read boundary, out-of-order stream-versus-completion delivery no longer drops valid tool-call state, duplicated conversation loading logic is consolidated, and regression coverage plus architecture docs describe and enforce the new behavior.