# Tasks: Frontend Architecture Review — murmur_web & murmur_demo

## Task List

Format: `- [ ] T001 [P] Description with file path`
- **T001, T002, …** — sequential task ID
- **[P]** — present only when the task can run in parallel with others
- Include the exact file path to create or modify in the description

Group tasks by user-story priority (P1 first). Each group should be an independently testable increment.

### P1 — Generic multi-agent workspace shell

- [x] T001 Update `/Users/vincent.min/Projects/murmur/apps/jido_murmur_web/lib/jido_murmur_web/components/artifact_panel.ex`, `/Users/vincent.min/Projects/murmur/apps/jido_murmur_web/priv/templates/components/artifact_panel.ex`, and `/Users/vincent.min/Projects/murmur/apps/jido_murmur_web/test/jido_murmur_web/components/artifact_panel_test.exs` so the generic artifact panel depends on explicit renderer registration and a safe fallback instead of built-in domain defaults.
- [x] T002 Update `/Users/vincent.min/Projects/murmur/apps/jido_murmur_web/lib/mix/tasks/jido_murmur_web.install.ex`, `/Users/vincent.min/Projects/murmur/apps/jido_murmur_web/test/mix/tasks/install_test.exs`, and the artifact component sources under `/Users/vincent.min/Projects/murmur/apps/jido_murmur_web/lib/jido_murmur_web/components/artifact_panel/` so the reusable package no longer presents arXiv-specific renderers as part of its generic install surface.
- [x] T003 Create `/Users/vincent.min/Projects/murmur/apps/murmur_demo/lib/murmur_web/artifacts/registry.ex` and `/Users/vincent.min/Projects/murmur/apps/murmur_demo/lib/murmur_web/artifacts/actions.ex`, then update `/Users/vincent.min/Projects/murmur/apps/murmur_demo/lib/murmur_web/live/workspace_live.ex` to delegate artifact rendering and follow-up actions through demo-owned integration modules.
- [x] T004 Update `/Users/vincent.min/Projects/murmur/apps/murmur_demo/lib/murmur_web/components/artifacts.ex`, `/Users/vincent.min/Projects/murmur/apps/murmur_demo/lib/murmur_web/components/artifacts/paper_list.ex`, `/Users/vincent.min/Projects/murmur/apps/murmur_demo/lib/murmur_web/components/artifacts/pdf_viewer.ex`, and `/Users/vincent.min/Projects/murmur/apps/murmur_demo/lib/murmur_web/components/artifacts/sql_results.ex` so `murmur_demo` owns SQL and arXiv artifact presentation through the new registry boundary.
- [x] T005 Update `/Users/vincent.min/Projects/murmur/apps/jido_murmur_web/test/jido_murmur_web/components/artifact_panel_test.exs`, `/Users/vincent.min/Projects/murmur/apps/murmur_demo/test/murmur_web/live/workspace_live_test.exs`, and `/Users/vincent.min/Projects/murmur/apps/murmur_demo/test/murmur_web/live/workspace_live_artifact_signal_test.exs` to verify the generic package remains domain-agnostic while the demo still supports SQL and arXiv artifact workflows.

### P1 — Consumer-owned domain presentation

- [x] T006 Update `/Users/vincent.min/Projects/murmur/apps/murmur_demo/lib/murmur_web/live/workspace_live.ex` and `/Users/vincent.min/Projects/murmur/apps/murmur_demo/lib/murmur_web/artifacts/actions.ex` so SQL re-execution and future artifact-specific actions are expressed as demo-owned behavior instead of direct plugin coupling in the workspace orchestrator.
- [x] T007 Update `/Users/vincent.min/Projects/murmur/apps/murmur_demo/test/murmur_web/live/workspace_live_integration_test.exs` and create or extend `/Users/vincent.min/Projects/murmur/apps/murmur_demo/test/murmur_web/live/workspace_live_artifact_actions_test.exs` to cover demo-owned artifact actions and safe fallback behavior for unsupported artifact types.

### P2 — Cohesive workspace interaction model

- [x] T008 Refactor `/Users/vincent.min/Projects/murmur/apps/jido_murmur_web/lib/jido_murmur_web/components/chat_message.ex`, `/Users/vincent.min/Projects/murmur/apps/jido_murmur_web/lib/jido_murmur_web/components/chat_stream.ex`, and `/Users/vincent.min/Projects/murmur/apps/jido_murmur_web/test/jido_murmur_web/components/chat_test.exs` to use consistent DaisyUI chat, collapse, and state patterns while preserving current chat capabilities.
- [x] T009 Create `/Users/vincent.min/Projects/murmur/apps/murmur_demo/lib/murmur_web/components/workspace/header.ex`, `/Users/vincent.min/Projects/murmur/apps/murmur_demo/lib/murmur_web/components/workspace/split_view.ex`, and `/Users/vincent.min/Projects/murmur/apps/murmur_demo/lib/murmur_web/components/workspace/unified_view.ex` to extract the main workspace presentation out of `/Users/vincent.min/Projects/murmur/apps/murmur_demo/lib/murmur_web/live/workspace_live.html.heex`.
- [x] T010 Update `/Users/vincent.min/Projects/murmur/apps/murmur_demo/lib/murmur_web/live/workspace_live.html.heex`, `/Users/vincent.min/Projects/murmur/apps/murmur_demo/lib/murmur_web/components/artifacts/task_board.ex`, and the new workspace components under `/Users/vincent.min/Projects/murmur/apps/murmur_demo/lib/murmur_web/components/workspace/` so the UI keeps split and unified chat plus the separate artifact panel, but uses a more coherent DaisyUI-based interaction model.
- [x] T011 Update `/Users/vincent.min/Projects/murmur/apps/murmur_demo/test/murmur_web/live/workspace_live_test.exs`, `/Users/vincent.min/Projects/murmur/apps/murmur_demo/test/murmur_web/live/workspace_live_integration_test.exs`, and `/Users/vincent.min/Projects/murmur/apps/murmur_demo/test/murmur_web/live/workspace_live_task_board_test.exs` to verify the refreshed UI preserves key flows, IDs, and empty or loading states.

### P2 — Maintainable frontend boundaries

- [x] T012 Extract non-rendering workspace helpers from `/Users/vincent.min/Projects/murmur/apps/murmur_demo/lib/murmur_web/live/workspace_live.ex` into focused modules such as `/Users/vincent.min/Projects/murmur/apps/murmur_demo/lib/murmur_web/live/workspace_state.ex` and update `/Users/vincent.min/Projects/murmur/apps/murmur_demo/test/murmur_web/live/workspace_live_helpers_test.exs` to target the new boundaries directly.
- [x] T013 Create `/Users/vincent.min/Projects/murmur/specs/decisions/ADR-001-frontend-boundary-ownership.md` and update `/Users/vincent.min/Projects/murmur/specs/Architecture/jido-murmur-web.md` plus `/Users/vincent.min/Projects/murmur/specs/Architecture/murmur-demo.md` so the generic-versus-demo frontend boundary is documented before the ticket is completed.

## Completion Criteria

All tasks checked off and acceptance criteria from Spec.md verified.