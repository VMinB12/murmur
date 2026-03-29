# Tasks: Artifact System Extraction

**Input**: Design documents from `/specs/003-artifact-extraction/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/jido-artifacts-api.md, quickstart.md

**Tests**: Included — the spec explicitly defines acceptance scenarios requiring unit test coverage.

**Organization**: Tasks grouped by user story. US4 (extraction) is foundational and precedes other stories.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Create the `jido_artifacts` umbrella app skeleton and configure dependencies

- [x] T001 Create `apps/jido_artifacts/` directory with `mix.exs` declaring deps: `{:jido, in_umbrella: true}, {:jido_signal, ...}, {:jido_action, ...}, {:phoenix_pubsub, "~> 2.0"}, {:jason, "~> 1.0"}`
- [x] T002 Create `apps/jido_artifacts/lib/jido_artifacts.ex` top-level module with `pubsub/0` config accessor
- [x] T003 [P] Create `apps/jido_artifacts/test/test_helper.exs` with ExUnit configuration

---

## Phase 2: Foundational — Package Extraction (US4 prerequisite)

**Purpose**: Move existing artifact modules from jido_murmur to jido_artifacts. MUST complete before API enhancements.

**⚠️ CRITICAL**: All user stories depend on the extracted package existing.

- [x] T004 [US4] Move `apps/jido_murmur/lib/jido_murmur/artifact.ex` to `apps/jido_artifacts/lib/jido_artifacts/artifact.ex`, rename module to `JidoArtifacts.Artifact`
- [x] T005 [US4] Move `apps/jido_murmur/lib/jido_murmur/artifact_plugin.ex` to `apps/jido_artifacts/lib/jido_artifacts/artifact_plugin.ex`, rename module to `JidoArtifacts.ArtifactPlugin`
- [x] T006 [US4] Move `apps/jido_murmur/lib/jido_murmur/actions/store_artifact.ex` to `apps/jido_artifacts/lib/jido_artifacts/actions/store_artifact.ex`, rename module to `JidoArtifacts.Actions.StoreArtifact`
- [x] T007 [US4] Delete original files from jido_murmur: `apps/jido_murmur/lib/jido_murmur/artifact.ex`, `artifact_plugin.ex`, `actions/store_artifact.ex`
- [x] T008 [US4] Update `apps/jido_murmur/mix.exs` to add `{:jido_artifacts, in_umbrella: true}` dependency
- [x] T009 [US4] Update all `JidoMurmur.Artifact` references in jido_murmur to `JidoArtifacts.Artifact` (imports, aliases, function calls)
- [x] T010 [US4] Update all `JidoMurmur.ArtifactPlugin` references in jido_murmur to `JidoArtifacts.ArtifactPlugin`
- [x] T011 [US4] Update all `JidoMurmur.Actions.StoreArtifact` references in jido_murmur to `JidoArtifacts.Actions.StoreArtifact`
- [x] T012 [US4] Update `apps/jido_arxiv/mix.exs` to depend on `{:jido_artifacts, in_umbrella: true}` instead of `jido_murmur` for artifact functionality
- [x] T013 [US4] Update all artifact references in `apps/jido_arxiv/` to use `JidoArtifacts.*` modules
- [x] T014 [US4] Update `apps/murmur_demo/mix.exs` to add `{:jido_artifacts, in_umbrella: true}` dependency
- [x] T015 [US4] Add `config :jido_artifacts, pubsub: Murmur.PubSub` to `config/config.exs`
- [x] T016 [US4] Update `ArtifactPlugin` to read PubSub from `:jido_artifacts` config via `JidoArtifacts.pubsub/0` instead of `JidoMurmur.pubsub/0`
- [x] T017 [US4] Update agent profile modules in `apps/murmur_demo/` to reference `JidoArtifacts.ArtifactPlugin` instead of `JidoMurmur.ArtifactPlugin`
- [x] T018 [US4] Verify umbrella compiles: run `mix compile` from repo root with zero errors

**Checkpoint**: Extraction complete. All modules live in jido_artifacts. Umbrella compiles. Existing behavior unchanged.

---

## Phase 3: User Story 1 — Tool Author Emits Artifacts with Custom Merge (Priority: P1) 🎯 MVP

**Goal**: Enhance `Artifact.emit/4` to accept `:merge` callback and ship built-in merge helpers in `JidoArtifacts.Merge`.

**Independent Test**: Call `emit/4` with various merge options and verify signal data contains correct merge results.

### Tests for User Story 1

- [x] T019 [P] [US1] Create `apps/jido_artifacts/test/jido_artifacts/merge_test.exs` with tests for `append/2`, `prepend/2`, `append_max/1`, `prepend_max/1`, `upsert_by/1` including nil-existing edge case
- [x] T020 [P] [US1] Create `apps/jido_artifacts/test/jido_artifacts/artifact_test.exs` with tests for `emit/4` with no merge (replace), with `merge: &Merge.append/2`, with `merge: Merge.append_max(50)`, and with custom function

### Implementation for User Story 1

- [x] T021 [P] [US1] Create `apps/jido_artifacts/lib/jido_artifacts/merge.ex` with `append/2`, `prepend/2`, `append_max/1`, `prepend_max/1`, `upsert_by/1` per contracts/jido-artifacts-api.md
- [x] T022 [US1] Rewrite `Artifact.emit/4` in `apps/jido_artifacts/lib/jido_artifacts/artifact.ex` to accept `:merge` keyword, apply merge eagerly from `ctx[:state][:artifacts]`, include `merge_result` in signal data when merge is provided, set `mode: :replace` when no merge

**Checkpoint**: Merge helpers work. emit/4 produces correct signal data with merge_result. Tests pass.

---

## Phase 4: User Story 2 — StoreArtifact Persists with Metadata Envelope (Priority: P1)

**Goal**: `StoreArtifact` wraps stored data in `%{data: ..., updated_at: ..., source: ..., version: ...}` envelope.

**Independent Test**: Run StoreArtifact with mock agent state and verify envelope structure, version increment, and nil-delete behavior.

### Tests for User Story 2

- [x] T023 [P] [US2] Create `apps/jido_artifacts/test/jido_artifacts/actions/store_artifact_test.exs` with tests for: create (version 1), update (version increment), delete (nil merge_result removes key), merge_result storage

### Implementation for User Story 2

- [x] T024 [US2] Rewrite `StoreArtifact.run/2` in `apps/jido_artifacts/lib/jido_artifacts/actions/store_artifact.ex` to wrap data in metadata envelope `%{data: ..., updated_at: DateTime.utc_now(), source: agent_id, version: n}`, increment version on update, delete key when merge_result is nil

**Checkpoint**: Stored artifacts include metadata envelope. Version increments. Nil deletes. Tests pass.

---

## Phase 5: User Story 3 — Artifact Signals Carry CloudEvents Identity (Priority: P2)

**Goal**: `emit/4` populates CloudEvents `source` and `subject` fields from action context.

**Independent Test**: Call emit/4 with context containing agent identity and verify signal struct fields.

### Tests for User Story 3

- [x] T025 [P] [US3] Add tests to `apps/jido_artifacts/test/jido_artifacts/artifact_test.exs` for: source set to `/jido_artifacts/#{name}`, subject set to `/agents/#{agent_id}` when present, subject is nil when no agent identity

### Implementation for User Story 3

- [x] T026 [US3] Update `Artifact.emit/4` in `apps/jido_artifacts/lib/jido_artifacts/artifact.ex` to set signal `source: "/jido_artifacts/#{name}"` and `subject: "/agents/#{agent_id}"` from `ctx[:state][:__agent_id__]`, defaulting subject to nil

**Checkpoint**: Signals carry CloudEvents identity. Degrades gracefully. Tests pass.

---

## Phase 6: User Story 5 — Scope Field Reserves Cross-Agent Support (Priority: P3)

**Goal**: `emit/4` accepts optional `:scope` keyword (`:agent` default, `:workspace` reserved).

**Independent Test**: Verify scope flows through signal data and workspace scope is handled.

### Tests for User Story 5

- [x] T027 [P] [US5] Add tests to `apps/jido_artifacts/test/jido_artifacts/artifact_test.exs` for: default scope is `:agent`, explicit `scope: :agent` works, `scope: :workspace` accepted in signal data

### Implementation for User Story 5

- [x] T028 [US5] Update `Artifact.emit/4` in `apps/jido_artifacts/lib/jido_artifacts/artifact.ex` to accept `:scope` keyword option, default to `:agent`, include scope in signal data
- [x] T029 [US5] Update `ArtifactPlugin.handle_signal/2` in `apps/jido_artifacts/lib/jido_artifacts/artifact_plugin.ex` to log warning when `scope: :workspace` is received (not yet implemented)

**Checkpoint**: Scope field reserved in API. Workspace scope warns at plugin level. Tests pass.

---

## Phase 7: User Story 6 — Renderer Unwraps Metadata Envelope (Priority: P2)

**Goal**: ArtifactPanel in jido_murmur_web unwraps the metadata envelope so renderers receive raw data.

**Independent Test**: Render artifact panel with envelope-format data and verify renderer gets only the data field.

### Implementation for User Story 6

- [x] T030 [US6] Update `apps/jido_murmur_web/lib/jido_murmur_web/components/artifact_panel.ex` to unwrap metadata envelope: if data is map with `:data` and `:version` keys, extract `.data`; otherwise pass through unchanged

**Checkpoint**: Renderers receive raw data regardless of envelope format. Backward compatible with old format.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Integration verification and documentation

- [x] T031 [P] Update `apps/jido_artifacts/lib/mix/tasks/jido_artifacts.install.ex` to add `config :jido_artifacts, pubsub: {App}.PubSub` (placeholder for 004-igniter-adoption)
- [x] T032 Run full umbrella test suite (`mix test`) from repo root — verify all existing tests pass with zero regressions
- [x] T033 Run `mix precommit` from repo root to verify Credo, Dialyxir, and formatting compliance

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational/Extraction (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories
- **US1 Merge (Phase 3)**: Depends on Phase 2 — can run parallel with US3, US5
- **US2 Envelope (Phase 4)**: Depends on Phase 2 — can run parallel with US1
- **US3 CloudEvents (Phase 5)**: Depends on Phase 2 — can run parallel with US1
- **US5 Scope (Phase 6)**: Depends on Phase 2 — can run parallel with US1
- **US6 Renderer (Phase 7)**: Depends on Phase 4 (needs envelope format to exist)
- **Polish (Phase 8)**: Depends on all user stories complete

### Parallel Opportunities

```
After Phase 2 (extraction) completes, these can run in parallel:
├── Phase 3: US1 (Merge) — apps/jido_artifacts/merge.ex + artifact.ex
├── Phase 4: US2 (Envelope) — apps/jido_artifacts/actions/store_artifact.ex
├── Phase 5: US3 (CloudEvents) — apps/jido_artifacts/artifact.ex (source/subject only)
└── Phase 6: US5 (Scope) — apps/jido_artifacts/artifact.ex (scope keyword only)

Then sequentially:
└── Phase 7: US6 (Renderer) — apps/jido_murmur_web/components/artifact_panel.ex
└── Phase 8: Polish
```

---

## Implementation Strategy

### MVP First (US4 + US1 + US2)

1. Complete Phase 1: Setup
2. Complete Phase 2: Extraction (US4) — umbrella compiles with renamed modules
3. Complete Phase 3: Merge callbacks (US1) — tool authors get new API
4. Complete Phase 4: Metadata envelope (US2) — stored artifacts have versioning
5. **STOP and VALIDATE**: Artifact system extracted, enhanced, all tests pass

### Incremental Delivery

1. Setup + Extraction → Package exists, backward-compatible
2. Add Merge (US1) → Tool authors get merge callbacks
3. Add Envelope (US2) → Stored artifacts versioned
4. Add CloudEvents (US3) → Signal tracing enabled
5. Add Scope (US5) → Forward-compatible API
6. Add Renderer unwrap (US6) → UI works with envelope format
7. Each story adds value without breaking previous stories

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story from spec.md
- US4 (extraction) is treated as Phase 2 (foundational) because all other stories depend on the extracted package
- US5 (scope) and US3 (CloudEvents) are small additions that can be done in parallel with US1/US2
- Commit after each phase checkpoint
