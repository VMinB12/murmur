# Tasks: Actor Identity And Display Projection Cleanup

## Task List

Format: `- [ ] T001 [P] Description with file path`
- **T001, T002, …** — sequential task ID
- **[P]** — present only when the task can run in parallel with others
- Include the exact file path to create or modify in the description

### P1 — Canonical Actor Boundary

- [x] T001 Create the canonical actor model in `apps/jido_murmur/lib/jido_murmur/actor_identity.ex` and refactor `apps/jido_murmur/lib/jido_murmur/ingress/metadata.ex` plus `apps/jido_murmur/lib/jido_murmur/runner.ex` to project explicit current-actor and origin-actor semantics, covering the change in `apps/jido_murmur/test/jido_murmur/ingress/metadata_test.exs` and `apps/murmur_demo/test/murmur/agents/inter_agent_test.exs`.
- [x] T002 Update canonical ingress and visible programmatic delivery handling in `apps/jido_murmur/lib/jido_murmur/ingress/input.ex`, `apps/jido_murmur/lib/jido_murmur/ingress/programmatic_delivery.ex`, and `apps/jido_murmur/lib/jido_murmur/signals/message_received.ex` so actor metadata is carried explicitly without reusing the overloaded runtime and UI sender contract, and cover it in `apps/jido_murmur/test/jido_murmur/ingress/input_test.exs` plus `apps/murmur_demo/test/murmur_web/live/workspace_live_test.exs`.
- [x] T003 Refactor `apps/jido_murmur/lib/jido_murmur/message_injector.ex` and related runtime-context callers to consume explicit actor identity fields instead of `runtime_context[:sender_name]`, and lock the behavior in `apps/murmur_demo/test/murmur/agents/message_injector_test.exs`.

### P2 — Canonical Display Projection

- [x] T004 Create the canonical display-message model in `apps/jido_murmur/lib/jido_murmur/display_message.ex` and refactor `apps/jido_murmur/lib/jido_murmur/ui_turn.ex` to emit it without sender inference or atom-versus-string key fallback, covering the projection in `apps/jido_murmur/test/jido_murmur/ui_turn_test.exs` and `apps/murmur_demo/test/murmur/agents/ui_turn_test.exs`.
- [x] T005 Migrate `apps/jido_murmur_web/lib/jido_murmur_web/components/chat_message.ex` to actor-aware labeling and styling helpers, removing raw `"You"` comparisons, and update `apps/jido_murmur_web/test/jido_murmur_web/components/chat_test.exs`.
- [x] T006 Migrate workspace rendering in `apps/murmur_demo/lib/murmur_web/components/workspace/unified_view.ex`, `apps/murmur_demo/lib/murmur_web/components/workspace/split_view.ex`, and `apps/murmur_demo/lib/murmur_web/live/workspace_live.html.heex` to consume canonical display messages and actor semantics consistently, and update `apps/murmur_demo/test/murmur_web/live/workspace_live_test.exs` plus `apps/murmur_demo/test/murmur_web/live/workspace_live_integration_test.exs`.
- [x] T007 Update optimistic local message creation and task-notification display handling in `apps/murmur_demo/lib/murmur_web/live/workspace_live.ex` so presentation wording is chosen at the edge instead of being stamped into runtime message data, and cover that behavior in `apps/murmur_demo/test/murmur_web/live/workspace_live_task_board_test.exs` and `apps/murmur_demo/test/murmur_web/live/workspace_live_persistence_test.exs`.

### P3 — Docs And Validation

- [x] T008 [P] Update architecture documentation in `specs/Architecture/jido-murmur.md`, `specs/Architecture/jido-murmur-web.md`, and `specs/Architecture/murmur-demo.md` to describe the canonical actor-identity boundary, the canonical display-message projection boundary, and the presentation-owned labeling rule.
- [x] T009 [P] Refresh focused helpers, fixtures, and regression coverage in `apps/jido_murmur/test/jido_murmur/ingress/metadata_test.exs`, `apps/jido_murmur/test/jido_murmur/ui_turn_test.exs`, `apps/jido_murmur_web/test/jido_murmur_web/components/chat_test.exs`, and `apps/murmur_demo/test/murmur_web/live/workspace_live_helpers_test.exs` so the new contract is locked in end-to-end.
- [x] T010 Run targeted runtime and workspace suites, then run `mix precommit` from `/Users/vincent.min/Projects/murmur`, covering at least `apps/jido_murmur/test/jido_murmur/ingress/metadata_test.exs`, `apps/jido_murmur/test/jido_murmur/ui_turn_test.exs`, `apps/jido_murmur_web/test/jido_murmur_web/components/chat_test.exs`, and `apps/murmur_demo/test/murmur_web/live/workspace_live_test.exs`.

## Completion Criteria

All acceptance criteria from `Spec.md` are satisfied, runtime and UI consumers share one explicit actor model plus one canonical display-message model, the cleaned-up projection path no longer depends on sender inference or display-label string heuristics, presentation-owned wording can change without changing runtime contracts, and documentation plus regression coverage describe and enforce the new boundary.