# Tasks: CloudEvents Signal Alignment

**Input**: Design documents from `/specs/005-cloudevents-alignment/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/signal-envelope.md, quickstart.md

**Tests**: Included — handler migration requires verification that no tuple patterns remain and all signals carry correct fields.

**Organization**: Tasks grouped by user story. US1 (subject fields) and US2 (signal envelope migration) are P1 and form the MVP.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Verify signal framework availability and prepare for typed module creation

- [ ] T001 Verify `use Jido.Signal` macro is available for typed signal definitions by checking `deps/jido_signal/lib/jido/signal.ex` for the `__using__/1` macro
- [ ] T002 [P] Create `apps/jido_murmur/lib/jido_murmur/signals/` directory
- [ ] T003 [P] Create `apps/jido_tasks/lib/jido_tasks/signals/` directory

---

## Phase 2: Foundational — Typed Signal Module Definitions (US4 prerequisite for US2)

**Purpose**: Define typed signal modules before migrating broadcasts. These modules serve as the canonical type registry.

**⚠️ CRITICAL**: Signal modules must exist before broadcast migration — they define the type strings and `new!/2` constructors used by producers.

### Tests for Foundational Phase

- [ ] T004 [P] Create `apps/jido_murmur/test/jido_murmur/signals/message_completed_test.exs` with tests for: valid signal creation with correct type/source/subject, schema validation rejects missing session_id or response
- [ ] T005 [P] Create `apps/jido_murmur/test/jido_murmur/signals/message_received_test.exs` with tests for: valid signal creation, schema validation rejects missing session_id or message
- [ ] T006 [P] Create `apps/jido_tasks/test/jido_tasks/signals/task_created_test.exs` with tests for: valid signal creation with `type: "task.created"`, subject includes workspace and task ID
- [ ] T007 [P] Create `apps/jido_tasks/test/jido_tasks/signals/task_updated_test.exs` with tests for: valid signal creation with `type: "task.updated"`, subject includes workspace and task ID

### Implementation for Foundational Phase

- [ ] T008 [P] [US4] Create `apps/jido_murmur/lib/jido_murmur/signals/message_completed.ex` — `use Jido.Signal` with type `"murmur.message.completed"`, source `"/jido_murmur/runner"`, data schema: `session_id` (required string), `response` (required term), subject pattern: `"/workspaces/#{wid}/agents/#{sid}"`
- [ ] T009 [P] [US4] Create `apps/jido_murmur/lib/jido_murmur/signals/message_received.ex` — `use Jido.Signal` with type `"murmur.message.received"`, source `"/jido_murmur/tell_action"`, data schema: `session_id` (required string), `message` (required map), subject pattern: `"/workspaces/#{wid}/agents/#{sid}"`
- [ ] T010 [P] [US4] Create `apps/jido_tasks/lib/jido_tasks/signals/task_created.ex` — `use Jido.Signal` with type `"task.created"`, source `"/jido_tasks/tools/add_task"`, data schema: `task` (required), subject pattern: `"/workspaces/#{wid}/tasks/#{tid}"`
- [ ] T011 [P] [US4] Create `apps/jido_tasks/lib/jido_tasks/signals/task_updated.ex` — `use Jido.Signal` with type `"task.updated"`, source `"/jido_tasks/tools/update_task"`, data schema: `task` (required), subject pattern: `"/workspaces/#{wid}/tasks/#{tid}"`

**Checkpoint**: All 4 typed signal modules compile. Schema validation works. Type strings and source URIs are canonical. Tests pass.

---

## Phase 3: User Story 1 — Signals Carry Entity Context via Subject Field (Priority: P1) 🎯 MVP

**Goal**: All signals emitted by the system populate the `subject` field with the entity path.

**Independent Test**: Create signals via typed modules and verify `subject` field follows the URI patterns from data-model.md.

### Tests for User Story 1

- [ ] T012 [P] [US1] Add subject-field-specific tests to `apps/jido_murmur/test/jido_murmur/signals/message_completed_test.exs` verifying subject is `"/workspaces/#{wid}/agents/#{sid}"` when workspace_id and session_id are provided
- [ ] T013 [P] [US1] Add subject-field-specific tests to `apps/jido_tasks/test/jido_tasks/signals/task_created_test.exs` verifying subject is `"/workspaces/#{wid}/tasks/#{tid}"`

### Implementation for User Story 1

- [ ] T014 [US1] Update `apps/jido_murmur/lib/jido_murmur/streaming_plugin.ex` — when broadcasting streaming signals from jido_ai, populate `subject` field with `"/agents/#{session_id}"` on signals that lack it
- [ ] T015 [US1] Update `apps/jido_murmur/lib/jido_murmur/runner.ex` — when creating message_completed signal, populate `subject` with `"/workspaces/#{workspace_id}/agents/#{session_id}"`
- [ ] T016 [US1] Update `apps/jido_murmur/lib/jido_murmur/tell_action.ex` — when creating new_message signal, populate `subject` with `"/workspaces/#{workspace_id}/agents/#{session_id}"`
- [ ] T017 [P] [US1] Update `apps/jido_tasks/lib/jido_tasks/tools/add_task.ex` — when creating task_created signal, populate `subject` with `"/workspaces/#{workspace_id}/tasks/#{task_id}"`
- [ ] T018 [P] [US1] Update `apps/jido_tasks/lib/jido_tasks/tools/update_task.ex` — when creating task_updated signal, populate `subject` with `"/workspaces/#{workspace_id}/tasks/#{task_id}"`

**Checkpoint**: All emitted signals carry meaningful `subject` fields. Entity routing possible from subject alone.

---

## Phase 4: User Story 2 — PubSub Messages Use Signal Envelope (Priority: P1)

**Goal**: Replace all 5 ad-hoc tuple patterns with `%Jido.Signal{}` broadcasts. Update all `handle_info/2` handlers atomically.

**⚠️ CRITICAL**: All 5 tuple migrations and ALL handler updates must land in a single commit. Partial migration causes silent message drops.

**Independent Test**: Subscribe to PubSub topics and verify all messages are `%Jido.Signal{}` structs.

### Tests for User Story 2

- [ ] T019 [P] [US2] Create `apps/jido_murmur/test/jido_murmur/signal_broadcast_test.exs` testing that `runner.ex` broadcasts `%Jido.Signal{type: "murmur.message.completed"}` instead of `{:message_completed, ...}` tuple
- [ ] T020 [P] [US2] Create `apps/jido_tasks/test/jido_tasks/signal_broadcast_test.exs` testing that `add_task.ex` broadcasts `%Jido.Signal{type: "task.created"}` and `update_task.ex` broadcasts `%Jido.Signal{type: "task.updated"}`

### Implementation for User Story 2 — Producer Side (broadcast replacements)

- [ ] T021 [US2] Migrate `apps/jido_murmur/lib/jido_murmur/runner.ex` — replace `{:message_completed, session_id, response}` broadcast with `%Jido.Signal{type: "murmur.message.completed", ...}` per contracts/signal-envelope.md
- [ ] T022 [US2] Migrate `apps/jido_murmur/lib/jido_murmur/tell_action.ex` — replace `{:new_message, session_id, msg}` broadcast with `%Jido.Signal{type: "murmur.message.received", ...}`
- [ ] T023 [US2] Migrate `apps/jido_murmur/lib/jido_murmur/streaming_plugin.ex` — replace `{:agent_signal, session_id, signal}` wrapper with direct `%Jido.Signal{}` broadcast (the inner signal is already a Signal struct)
- [ ] T024 [P] [US2] Migrate `apps/jido_tasks/lib/jido_tasks/tools/add_task.ex` — replace `{:task_created, task}` broadcast with `%Jido.Signal{type: "task.created", ...}`
- [ ] T025 [P] [US2] Migrate `apps/jido_tasks/lib/jido_tasks/tools/update_task.ex` — replace `{:task_updated, task}` broadcast with `%Jido.Signal{type: "task.updated", ...}`

### Implementation for User Story 2 — Consumer Side (handler updates)

- [ ] T026 [US2] Update `apps/murmur_demo/lib/murmur_web/live/workspace_live.ex` — replace ALL tuple `handle_info/2` patterns with `%Jido.Signal{}` struct matching per contracts/signal-envelope.md: match on `type` field instead of tuple atoms
- [ ] T027 [US2] Update artifact handler in `workspace_live.ex` — replace `{:artifact_update, sid, name, data, mode}` pattern with `%Jido.Signal{type: "artifact." <> _name}` pattern (artifact broadcasts from spec 003 or existing code)
- [ ] T028 [US2] Update streaming handler in `workspace_live.ex` — replace `{:agent_signal, _sid, signal}` pattern with direct `%Jido.Signal{type: "ai." <> _}` matching (no more wrapper tuple)
- [ ] T029 [US2] Grep entire codebase for remaining tuple patterns: `{:task_created`, `{:task_updated`, `{:message_completed`, `{:new_message`, `{:agent_signal`, `{:artifact_update` — verify zero matches in broadcast or handler code

**Checkpoint**: Zero tuple broadcasts remain. All handlers use `%Jido.Signal{}` matching. Full test suite passes. SC-004 met.

---

## Phase 5: User Story 3 — Non-Signal ID Generation Uses Standard UUID (Priority: P2)

**Goal**: Replace `Signal.ID.generate!()` calls at non-signal sites with `Uniq.UUID.uuid7()`.

**Independent Test**: Grep for `Signal.ID.generate!()` and verify all remaining uses are in actual signal contexts.

- [ ] T030 [US3] Search codebase for `Signal.ID.generate!()` usage in `apps/jido_murmur/` and `apps/jido_tasks/` — identify call sites that are non-signal contexts (message IDs, tracking IDs)
- [ ] T031 [US3] Replace non-signal `Signal.ID.generate!()` calls with `Uniq.UUID.uuid7()` in identified files (expected: `tell_action.ex` message ID, any tracking ID generation)

**Checkpoint**: `Signal.ID.generate!()` only used in signal construction. Non-signal IDs use `Uniq.UUID.uuid7()`.

---

## Phase 6: User Story 5 — Signal Event Catalog Documentation (Priority: P3)

**Goal**: Create developer reference document listing all signal types across the ecosystem.

- [ ] T032 [US5] Create `docs/signal-catalog.md` with table of all signal types per contracts/signal-envelope.md Signal Type Registry: type, source, subject pattern, data fields, handling plugins, PubSub topics
- [ ] T033 [US5] Add "How to add a new signal type" section to `docs/signal-catalog.md` with step-by-step guide: create typed module, register in catalog, update handlers

**Checkpoint**: Developers can discover all signal types from the catalog document. SC-003 met.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Integration verification and final validation

- [ ] T034 Run full umbrella test suite (`mix test`) from repo root — verify all existing tests pass with zero regressions
- [ ] T035 Run `mix precommit` from repo root to verify Credo, Dialyxir, and formatting compliance
- [ ] T036 Verify SC-001: grep for signals without `subject` field population in production code — should find zero
- [ ] T037 Verify SC-002: grep for tuple-pattern `handle_info` matching on PubSub messages — should find zero

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational/Typed Modules (Phase 2)**: Depends on Phase 1 — defines signal types used by US1 and US2
- **US1 Subject Fields (Phase 3)**: Depends on Phase 2 — needs typed modules for signal construction
- **US2 Signal Envelope (Phase 4)**: Depends on Phase 2 and Phase 3 — needs typed modules AND subject field population
- **US3 UUID Migration (Phase 5)**: Depends on Phase 1 only — independent refactor
- **US5 Catalog (Phase 6)**: Depends on Phase 2 and Phase 4 — needs final signal type list
- **Polish (Phase 7)**: Depends on all user stories complete

### Parallel Opportunities

```
After Phase 1 (setup):
├── Phase 2: Foundational (typed signal modules) — all [P] tasks
└── Phase 5: US3 (UUID migration) — independent of signal modules

After Phase 2 (typed modules):
├── Phase 3: US1 (subject fields) — producer-side changes
└── (Phase 5 may already be done)

After Phase 3 (subject fields):
└── Phase 4: US2 (envelope migration) — ATOMIC commit required

After Phase 4 (envelope done):
└── Phase 6: US5 (catalog documentation)
└── Phase 7: Polish
```

### Atomic Migration Constraint

Phase 4 tasks T021–T029 **MUST** be committed together. Partial migration where some producers broadcast signals but some handlers still match tuples will cause silent message drops. Approach:

1. Complete all producer-side changes (T021–T025)
2. Complete all consumer-side changes (T026–T028)
3. Run full verification (T029)
4. Commit all changes in a single commit

---

## Implementation Strategy

### MVP First (US1 + US2)

1. Complete Phase 1: Setup
2. Complete Phase 2: Typed signal modules (provides constructors)
3. Complete Phase 3: Subject fields populated on all signals
4. Complete Phase 4: Full envelope migration (atomic)
5. **STOP and VALIDATE**: All PubSub messages are proper signals with subject fields. Zero tuples remain.

### Incremental Delivery

1. Setup + Typed modules → Signal types defined, constructors available
2. Add subject fields (US1) → Entity context on all signals
3. Atomic envelope migration (US2) → All PubSub standardized (MVP complete)
4. UUID cleanup (US3) → Semantic clarity
5. Signal catalog (US5) → Developer documentation
6. Each story adds value; US2 is the high-risk single-commit step

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story from spec.md
- US4 (typed signal modules) is in the Foundational phase because it enables US1 and US2
- The `{:agent_signal, sid, signal}` tuple is special — the inner `signal` is already a `%Jido.Signal{}`. Migration for this pattern is removing the wrapper tuple, not creating a new signal.
- If spec 003 (artifact extraction) is implemented first, `ArtifactPlugin` broadcasts already produce signals. Otherwise, artifact broadcasts also need migration in Phase 4.
- Total: 37 tasks across 7 phases
