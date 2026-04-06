# Tasks: Core-Owned Visible Ingress Messages

## Task List

Format: `- [ ] T001 [P] Description with file path`
- **T001, T002, …** — sequential task ID
- **[P]** — present only when the task can run in parallel with others
- Include the exact file path to create or modify in the description

### P1 — Canonical Direct Ingress Ownership

- [ ] T001 Extend `apps/jido_murmur/lib/jido_murmur/ingress.ex`, `apps/jido_murmur/lib/jido_murmur/ingress/input.ex`, and any new helper under `apps/jido_murmur/lib/jido_murmur/ingress/` so direct human ingress emits a Murmur-owned visible user-message contract instead of relying on `WorkspaceLive` to mint canonical `DisplayMessage.user(...)` structs.
- [ ] T002 Align `apps/jido_murmur/lib/jido_murmur/ingress/programmatic_delivery.ex` with the direct-send path so visible programmatic and direct human ingress share one canonical message contract and metadata shape.
- [ ] T003 Update `apps/murmur_demo/lib/murmur_web/live/workspace_live.ex` to remove local canonical direct-message creation, replace it with transient pending-send presentation state, and reconcile that state when the Murmur-owned canonical message arrives.
- [ ] T004 Update `apps/murmur_demo/test/murmur_web/live/workspace_live_test.exs` and any related helper tests to cover direct sends, pending-state reconciliation, and no-duplicate behavior in both split and unified chat flows.

### P2 — Reconnect And Documentation

- [ ] T005 Add or update regression coverage in `apps/jido_murmur/test/jido_murmur/ingress/` and `apps/murmur_demo/test/murmur_web/live/` so refresh/remount behavior verifies canonical identity and first-seen metadata for direct human messages.
- [ ] T006 [P] Update `specs/Architecture/conversation-read-model.md`, `specs/Architecture/murmur-demo.md`, and `specs/Architecture/jido-murmur.md` to document that visible top-level ingress messages are core-owned for both direct and programmatic sources.

## Completion Criteria

All acceptance criteria from `Spec.md` are satisfied, `WorkspaceLive` no longer mints canonical direct human display messages, direct and programmatic visible ingress share one Murmur-owned contract, and the UI preserves responsiveness through explicit pending presentation state rather than canonical message creation.