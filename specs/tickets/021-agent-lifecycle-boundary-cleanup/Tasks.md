# Tasks: Agent Lifecycle Boundary Cleanup

## Task List

Format: `- [ ] T001 [P] Description with file path`
- **T001, T002, …** — sequential task ID
- **[P]** — present only when the task can run in parallel with others
- Include the exact file path to create or modify in the description

### P1 — Core Lifecycle Ownership

- [ ] T001 Extend `apps/jido_murmur/lib/jido_murmur/agent_helper.ex` or add a dedicated lifecycle module under `apps/jido_murmur/lib/jido_murmur/` that owns session start, stop, and storage-cleanup policy needed by the demo workspace flows.
- [ ] T002 Update `apps/murmur_demo/lib/murmur_web/live/workspace_live.ex` to replace local thaw/start and cleanup policy with calls to the core lifecycle API for mount, add-agent, remove-agent, and clear-team flows.
- [ ] T003 Add or update regression coverage in `apps/murmur_demo/test/murmur_web/live/workspace_live_test.exs` and any relevant integration tests so lifecycle-sensitive flows preserve current behavior after the boundary cleanup.

### P2 — Documentation And Reuse

- [ ] T004 [P] Update `specs/Architecture/murmur-demo.md` and `specs/Architecture/jido-murmur.md` to document the lifecycle ownership change if module responsibilities change materially.
- [ ] T005 Add focused tests or documentation around the new lifecycle API in `apps/jido_murmur/test/jido_murmur/` so future host apps have one obvious reuse path.

## Completion Criteria

All acceptance criteria from `Spec.md` are satisfied, `WorkspaceLive` no longer duplicates Murmur's lifecycle policy, core exposes the lifecycle surface the demo needs, and current workspace flows behave the same after the cleanup.