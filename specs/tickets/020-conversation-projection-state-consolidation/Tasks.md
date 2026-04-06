# Tasks: Conversation Projection State Consolidation

## Task List

Format: `- [ ] T001 [P] Description with file path`
- **T001, T002, …** — sequential task ID
- **[P]** — present only when the task can run in parallel with others
- Include the exact file path to create or modify in the description

### P1 — Shared Canonical Projection State

- [ ] T001 Extract or centralize assistant-step assembly rules used by `apps/jido_murmur/lib/jido_murmur/conversation_read_model.ex` and `apps/jido_murmur/lib/jido_murmur/conversation_read_model/entry_projector.ex` into a shared canonical projection boundary under `apps/jido_murmur/lib/jido_murmur/conversation_read_model/`.
- [ ] T002 Update `apps/jido_murmur/lib/jido_murmur/conversation_projector.ex` so ETS stores richer canonical read-model state instead of only rendered message lists, while preserving the existing snapshot API for callers.
- [ ] T003 Refactor completion reconciliation and incremental signal application in `apps/jido_murmur/lib/jido_murmur/conversation_projector.ex` and `apps/jido_murmur/lib/jido_murmur/conversation_read_model.ex` to operate on the shared canonical state model.
- [ ] T004 Add or update regression coverage in `apps/jido_murmur/test/jido_murmur/conversation_read_model_test.exs` and `apps/jido_murmur/test/jido_murmur/conversation_projector_test.exs` so live reduction and persisted replay produce equivalent assistant-step output for multi-step tool-using runs.

### P2 — Documentation And Guardrails

- [ ] T005 [P] Update `specs/Architecture/conversation-read-model.md` and `specs/Architecture/jido-murmur.md` to document the consolidated projector-state boundary if the internal ownership model changes materially.
- [ ] T006 Add focused assertions or test helpers in `apps/jido_murmur/test/jido_murmur/` that make future drift between replay and live reduction easier to catch.

## Completion Criteria

All acceptance criteria from `Spec.md` are satisfied, assistant-step assembly rules are no longer duplicated across live and replay paths, `ConversationProjector` retains richer canonical state internally, and ticket-017 behavior remains unchanged while the code becomes smaller and easier to reason about.