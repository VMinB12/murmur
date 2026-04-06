# Tasks: Conversation Read Model And Streaming Consistency

## Task List

Format: `- [ ] T001 [P] Description with file path`
- **T001, T002, …** — sequential task ID
- **[P]** — present only when the task can run in parallel with others
- Include the exact file path to create or modify in the description

### P1 — Canonical Conversation Read Boundary

- [x] T001 Create the canonical conversation model and projector in `apps/jido_murmur/lib/jido_murmur/conversation_read_model.ex`, `apps/jido_murmur/lib/jido_murmur/conversation_read_model/turn.ex`, and `apps/jido_murmur/lib/jido_murmur/conversation_projector.ex`, covering persisted and live turn lifecycle reduction in `apps/jido_murmur/test/jido_murmur/conversation_projector_test.exs`.
- [x] T002 Add a Murmur-owned conversation update contract in `apps/jido_murmur/lib/jido_murmur/signals/conversation_updated.ex` and expose projector-backed snapshot/loading helpers in `apps/jido_murmur/lib/jido_murmur/agent_helper.ex`, covering the new contract in `apps/jido_murmur/test/jido_murmur/agent_helper_test.exs`.
- [x] T003 Propagate stable turn identity and tool-call identity through `apps/jido_murmur/lib/jido_murmur/streaming_plugin.ex`, `apps/jido_murmur/lib/jido_murmur/runner.ex`, `apps/jido_murmur/lib/jido_murmur/signals/message_completed.ex`, and `apps/jido_murmur/lib/jido_murmur/llm/mock.ex`, locking out-of-order reconciliation behavior in `apps/jido_murmur/test/jido_murmur/conversation_projector_test.exs`.
- [x] T004 Refactor `apps/jido_murmur/lib/jido_murmur/ui_turn.ex` and `apps/jido_murmur/lib/jido_murmur/display_message.ex` so finalized thread projection reconciles through the canonical conversation boundary instead of remaining a standalone richer rendering path, and update `apps/jido_murmur/test/jido_murmur/ui_turn_test.exs`.

### P2 — LiveView And Helper Integration

- [x] T005 Replace direct raw `ai.*` rendering and the ad hoc `%{content, thinking, tool_calls, usage}` streaming state in `apps/murmur_demo/lib/murmur_web/live/workspace_live.ex` with consumption of the Murmur-owned conversation update contract and projector-backed snapshots, covering late-signal reconciliation after completion in `apps/murmur_demo/test/murmur_web/live/workspace_live_test.exs`.
- [x] T006 Consolidate duplicated live-versus-storage conversation loading in `apps/jido_murmur/lib/jido_murmur/agent_helper.ex` and `apps/murmur_demo/lib/murmur_web/live/workspace_state.ex` behind the canonical projector-backed API, updating `apps/murmur_demo/test/murmur_web/live/workspace_live_helpers_test.exs`.
- [x] T007 Adapt `apps/jido_murmur_web/lib/jido_murmur_web/components/chat_stream.ex`, `apps/jido_murmur_web/lib/jido_murmur_web/components/chat_message.ex`, `apps/murmur_demo/lib/murmur_web/components/workspace/split_view.ex`, and `apps/murmur_demo/lib/murmur_web/components/workspace/unified_view.ex` to render the same canonical turn state, removing or reducing redundant rendering abstractions if the shared model makes them unnecessary, and update `apps/jido_murmur_web/test/jido_murmur_web/components/chat_test.exs` plus `apps/murmur_demo/test/murmur_web/live/workspace_live_integration_test.exs`.

### P3 — Regression Coverage And Docs

- [x] T008 Add regression coverage for out-of-order completion, reconnect, and tool-call visibility in `apps/murmur_demo/test/murmur_web/live/workspace_live_test.exs` and `apps/murmur_demo/test/murmur_web/live/workspace_live_reconnect_test.exs`, including a case where `murmur.message.completed` arrives before later `ai.llm.response` or `ai.tool.result` signals.
- [x] T009 [P] Update `specs/Architecture/jido-murmur.md`, `specs/Architecture/jido-murmur-web.md`, and `specs/Architecture/murmur-demo.md` to document the core-owned conversation projector and Murmur-owned UI update contract, and update `specs/decisions/ADR-005-canonical-conversation-read-model.md` to `Accepted` if the implemented shape confirms the proposed decision.
- [x] T010 Run focused suites for `apps/jido_murmur/test/jido_murmur/conversation_projector_test.exs`, `apps/jido_murmur/test/jido_murmur/ui_turn_test.exs`, `apps/jido_murmur_web/test/jido_murmur_web/components/chat_test.exs`, `apps/murmur_demo/test/murmur_web/live/workspace_live_test.exs`, and `apps/murmur_demo/test/murmur_web/live/workspace_live_integration_test.exs`, then run `mix precommit` from `/Users/vincent.min/Projects/murmur`.

## Completion Criteria

All acceptance criteria from `Spec.md` are satisfied, live and refreshed chat rendering consume one core-owned conversation projector and Murmur-owned UI update contract, out-of-order stream-versus-completion delivery no longer drops valid tool-call state, duplicated conversation loading logic is consolidated, and regression coverage plus architecture docs describe and enforce the new behavior.