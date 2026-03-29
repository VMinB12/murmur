# Tasks: Platform Infrastructure Improvements

**Input**: Design documents from `/specs/006-platform-improvements/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/platform-contracts.md, quickstart.md

**Tests**: Included — config validation, topic helpers, telemetry, and behaviour all benefit from unit tests.

**Organization**: Tasks grouped by user story. US2 (workspace_id threading) is foundational and precedes US1 (topic naming).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Create new module files and verify telemetry dependency availability

- [ ] T001 Verify `:telemetry` dependency is available in `apps/jido_tasks/mix.exs` deps (should be transitive via phoenix)
- [ ] T002 [P] Create `apps/jido_murmur/lib/jido_murmur/topics.ex` placeholder module `JidoMurmur.Topics`
- [ ] T003 [P] Create `apps/jido_murmur/lib/jido_murmur/config.ex` placeholder module `JidoMurmur.Config`
- [ ] T004 [P] Create `apps/jido_murmur/lib/jido_murmur/agent_profile.ex` placeholder module `JidoMurmur.AgentProfile`
- [ ] T005 [P] Create `apps/jido_tasks/lib/jido_tasks/config.ex` placeholder module `JidoTasks.Config`

---

## Phase 2: Foundational — Workspace Context Threading (US2)

**Purpose**: Ensure plugins have access to `workspace_id` from agent state. MUST complete before topic migration.

**⚠️ CRITICAL**: US1 (topic naming) requires `workspace_id` in plugin context. This phase makes that available.

### Tests for Foundational Phase

- [ ] T006 [P] Create `apps/jido_murmur/test/jido_murmur/workspace_context_test.exs` with tests for: plugin `handle_signal/2` extracts `workspace_id` from agent state, falls back gracefully when `workspace_id` is absent

### Implementation for Foundational Phase

- [ ] T007 [US2] Update `apps/jido_murmur/lib/jido_murmur/streaming_plugin.ex` — extract `workspace_id` from `agent.state` in `handle_signal/2`, pass to PubSub broadcast topic construction
- [ ] T008 [US2] Update `apps/jido_murmur/lib/jido_murmur/artifact_plugin.ex` (or `apps/jido_artifacts/lib/jido_artifacts/artifact_plugin.ex` if spec 003 is done) — extract `workspace_id` from agent state, pass to PubSub broadcast topic construction
- [ ] T009 [US2] Update `apps/jido_murmur/lib/jido_murmur/runner.ex` — ensure `workspace_id` is threaded through agent execution context and available to plugins
- [ ] T010 [US2] Verify backward compatibility: when agent state lacks `workspace_id`, plugins fall back to session-only topic or log a warning

**Checkpoint**: All plugins can access `workspace_id`. Backward compatible when absent.

---

## Phase 3: User Story 1 — Consistent PubSub Topic Naming (Priority: P1) 🎯 MVP

**Goal**: Centralize all PubSub topic construction in `JidoMurmur.Topics` with workspace-scoped hierarchical format.

**Independent Test**: Call topic functions and verify format. Grep codebase for inline topic strings.

### Tests for User Story 1

- [ ] T011 [P] [US1] Create `apps/jido_murmur/test/jido_murmur/topics_test.exs` with tests for: `agent_artifacts/2` returns `"workspace:{wid}:agent:{sid}:artifacts"`, `agent_stream/2` returns `"workspace:{wid}:agent:{sid}:stream"`, `agent_messages/2` returns `"workspace:{wid}:agent:{sid}:messages"`, `workspace_tasks/1` returns `"workspace:{wid}:tasks"`, `workspace/1` returns `"workspace:{wid}"`

### Implementation for User Story 1

- [ ] T012 [US1] Implement `JidoMurmur.Topics` in `apps/jido_murmur/lib/jido_murmur/topics.ex` with all 5 functions per contracts/platform-contracts.md and data-model.md topic format
- [ ] T013 [US1] Update `apps/jido_murmur/lib/jido_murmur/streaming_plugin.ex` — replace inline `"agent_stream:#{session_id}"` topic with `Topics.agent_stream(workspace_id, session_id)`
- [ ] T014 [US1] Update `apps/jido_murmur/lib/jido_murmur/artifact_plugin.ex` (or jido_artifacts equivalent) — replace inline `"agent_artifacts:#{session_id}"` topic with `Topics.agent_artifacts(workspace_id, session_id)`
- [ ] T015 [US1] Update `apps/jido_murmur/lib/jido_murmur/runner.ex` — replace inline `"workspace:#{wid}:agent:#{sid}"` topic with `Topics.agent_messages(workspace_id, session_id)`
- [ ] T016 [US1] Update `apps/jido_murmur/lib/jido_murmur/tell_action.ex` — replace inline topic strings with `Topics` function calls
- [ ] T017 [US1] Update `apps/jido_tasks/lib/jido_tasks/tools/add_task.ex` — replace inline `"jido_tasks:tasks:#{workspace_id}"` topic with `Topics.workspace_tasks(workspace_id)` (add `JidoMurmur.Topics` as import or alias)
- [ ] T018 [US1] Update `apps/jido_tasks/lib/jido_tasks/tools/update_task.ex` — replace inline topic string with `Topics.workspace_tasks(workspace_id)`
- [ ] T019 [US1] Update `apps/murmur_demo/lib/murmur_web/live/workspace_live.ex` — update all PubSub subscriptions to use `Topics` function calls instead of inline topic strings
- [ ] T020 [US1] Grep entire codebase for remaining inline PubSub topic strings: patterns `"agent_artifacts:`, `"agent_stream:`, `"jido_tasks:tasks:` — verify zero matches outside of `Topics` module

**Checkpoint**: All PubSub topics constructed via centralized `Topics` module. Zero inline topic strings remain. SC-001 met.

---

## Phase 4: User Story 3 — Clear Error on Missing Configuration (Priority: P2)

**Goal**: Startup validation for required config keys with actionable error messages.

**Independent Test**: Remove config keys and verify error message format.

### Tests for User Story 3

- [ ] T021 [P] [US3] Create `apps/jido_murmur/test/jido_murmur/config_test.exs` with tests for: `validate!/0` passes with all keys present, raises with clear message listing missing `:repo` key, raises with multiple missing keys
- [ ] T022 [P] [US3] Create `apps/jido_tasks/test/jido_tasks/config_test.exs` with tests for: `validate!/0` passes with all keys, raises listing missing `:repo` or `:pubsub`

### Implementation for User Story 3

- [ ] T023 [US3] Implement `JidoMurmur.Config.validate!/0` in `apps/jido_murmur/lib/jido_murmur/config.ex` — check required keys `[:repo, :pubsub, :jido_mod, :otp_app]` from `Application.get_env(:jido_murmur, key)`, raise with error format from data-model.md including missing key names and remediation config snippet
- [ ] T024 [US3] Implement `JidoTasks.Config.validate!/0` in `apps/jido_tasks/lib/jido_tasks/config.ex` — check required keys `[:repo, :pubsub]` from `Application.get_env(:jido_tasks, key)`, raise with error format and remediation instructions
- [ ] T025 [US3] Call `JidoMurmur.Config.validate!/0` from `apps/jido_murmur/lib/jido_murmur/supervisor.ex` `init/1` callback (or application startup)
- [ ] T026 [US3] Call `JidoTasks.Config.validate!/0` from `apps/jido_tasks/lib/jido_tasks/supervisor.ex` or appropriate startup point

**Checkpoint**: Missing config produces clear, actionable error messages at startup. SC-003 met.

---

## Phase 5: User Story 4 — Telemetry Events for Task Operations (Priority: P3)

**Goal**: Task create/update/list operations emit telemetry events per `:telemetry.span/3` convention.

**Independent Test**: Attach telemetry handler, perform operations, verify events emitted.

### Tests for User Story 4

- [ ] T027 [P] [US4] Create `apps/jido_tasks/test/jido_tasks/tasks_telemetry_test.exs` with tests for: `:telemetry.attach/4` captures `[:jido_tasks, :task, :create, :stop]` event with `duration` and `task_id`, captures `[:jido_tasks, :task, :update, :stop]` with `old_status` and `new_status`, captures `[:jido_tasks, :task, :list, :stop]` with `count`

### Implementation for User Story 4

- [ ] T028 [US4] Wrap task creation in `apps/jido_tasks/lib/jido_tasks/tasks.ex` (or context module) with `:telemetry.span([:jido_tasks, :task, :create], metadata, fn -> ... end)` per contracts/platform-contracts.md
- [ ] T029 [US4] Wrap task update in same context module with `:telemetry.span([:jido_tasks, :task, :update], metadata, fn -> ... end)` including `old_status` and `new_status` in metadata
- [ ] T030 [US4] Wrap task listing in same context module with `:telemetry.span([:jido_tasks, :task, :list], metadata, fn -> ... end)` including `count` in result metadata

**Checkpoint**: All task operations emit telemetry events. Handlers can capture timing and metadata. SC-004 met.

---

## Phase 6: User Story 5 — Typed Agent Profile Behaviour (Priority: P3)

**Goal**: Define `JidoMurmur.AgentProfile` behaviour and adopt it in existing profile modules.

**Independent Test**: Create a profile missing a callback and verify compiler warning.

### Tests for User Story 5

- [ ] T031 [P] [US5] Create `apps/jido_murmur/test/jido_murmur/agent_profile_test.exs` with tests for: a module implementing all callbacks compiles without warnings, behaviour module exports all callback definitions

### Implementation for User Story 5

- [ ] T032 [US5] Implement `JidoMurmur.AgentProfile` behaviour in `apps/jido_murmur/lib/jido_murmur/agent_profile.ex` with `@callback` definitions: `name/0`, `description/0`, `system_prompt/0`, `tools/0`, `plugins/0`, `opts/0` per contracts/platform-contracts.md
- [ ] T033 [P] [US5] Add `@behaviour JidoMurmur.AgentProfile` to `apps/murmur_demo/lib/murmur/agents/profiles/general_agent.ex`
- [ ] T034 [P] [US5] Add `@behaviour JidoMurmur.AgentProfile` to `apps/murmur_demo/lib/murmur/agents/profiles/arxiv_agent.ex`
- [ ] T035 [US5] Verify both profile modules compile without missing-callback warnings

**Checkpoint**: Behaviour defined. Existing profiles annotated. Compiler validates callbacks. SC-005 met.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Integration verification and final validation

- [ ] T036 Run full umbrella test suite (`mix test`) from repo root — verify all existing tests pass with zero regressions
- [ ] T037 Run `mix precommit` from repo root to verify Credo, Dialyxir, and formatting compliance
- [ ] T038 Verify SC-001: grep for inline PubSub topic strings outside `Topics` module — should find zero
- [ ] T039 Verify SC-002: confirm all PubSub topics include workspace context

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational/workspace_id (Phase 2)**: Depends on Phase 1 — BLOCKS US1 (topic naming needs workspace_id)
- **US1 Topic Naming (Phase 3)**: Depends on Phase 2 — needs workspace_id available
- **US3 Config Validation (Phase 4)**: Depends on Phase 1 only — independent of topic work
- **US4 Telemetry (Phase 5)**: Depends on Phase 1 only — independent of all other stories
- **US5 Profile Behaviour (Phase 6)**: Depends on Phase 1 only — independent of all other stories
- **Polish (Phase 7)**: Depends on all user stories complete

### Parallel Opportunities

```
After Phase 1 (setup):
├── Phase 2: Foundational (workspace_id threading) — prerequisite for US1
├── Phase 4: US3 (config validation) — independent
├── Phase 5: US4 (telemetry) — independent
└── Phase 6: US5 (profile behaviour) — independent

After Phase 2:
└── Phase 3: US1 (topic naming) — the main migration

After all phases:
└── Phase 7: Polish
```

### Migration Constraint

Phase 3 PubSub topic migration (T013–T019) must be coordinated: update ALL subscribers (LiveView) and publishers (plugins, tools) together. Old topic strings and new topic strings are incompatible, so partial migration breaks routing.

---

## Implementation Strategy

### MVP First (US2 + US1)

1. Complete Phase 1: Setup
2. Complete Phase 2: workspace_id threading (prerequisite)
3. Complete Phase 3: Topic naming centralized
4. **STOP and VALIDATE**: All PubSub topics use `Topics` module with workspace context. Zero inline strings.

### Incremental Delivery

1. Setup → Module placeholders created
2. workspace_id threading (US2) → Plugins have workspace context
3. Topic naming (US1) → All topics centralized and consistent (MVP)
4. Config validation (US3) → Clear startup errors
5. Telemetry (US4) → Task observability
6. Profile behaviour (US5) → Compile-time validation for profiles
7. Each story is independent after foundational phase (except US1 depends on US2)

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story from spec.md
- US2 (workspace_id) is in the Foundational phase because US1 (topics) requires it
- If spec 005 (CloudEvents) is implemented first, PubSub broadcasts already use `%Jido.Signal{}` — topic migration only changes the topic string, not the message format
- If spec 003 (artifact extraction) is implemented first, `ArtifactPlugin` is in `jido_artifacts` not `jido_murmur` — adjust file paths for T008 and T014 accordingly
- The `JidoMurmur.Topics` module is used by both `jido_murmur` and `jido_tasks` — `jido_tasks` will need to depend on `jido_murmur` for topic functions or have topics duplicated
- Total: 39 tasks across 7 phases
