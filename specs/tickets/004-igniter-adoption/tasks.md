# Tasks: Igniter Adoption

**Input**: Design documents from `/specs/004-igniter-adoption/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/install-tasks.md, quickstart.md

**Tests**: Included — install task idempotency and guard pattern behavior require verification.

**Organization**: Tasks grouped by user story. US1 (jido_murmur install) is the MVP.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Add Igniter as optional dependency to all packages

- [X] T001 [P] Add `{:igniter, "~> 0.7", optional: true, runtime: false}` to `apps/jido_murmur/mix.exs` deps
- [X] T002 [P] Add `{:igniter, "~> 0.7", optional: true, runtime: false}` to `apps/jido_tasks/mix.exs` deps
- [X] T003 [P] Add `{:igniter, "~> 0.7", optional: true, runtime: false}` to `apps/jido_murmur_web/mix.exs` deps
- [X] T004 [P] Add `{:igniter, "~> 0.7", optional: true, runtime: false}` to `apps/jido_artifacts/mix.exs` deps (from spec 003)
- [X] T005 Run `mix deps.get` from repo root to fetch Igniter

---

## Phase 2: Foundational — Guard Pattern & Fallback

**Purpose**: Establish the guard pattern convention and fallback task. MUST be done before any Igniter task implementation.

**⚠️ CRITICAL**: The guard pattern is the safety mechanism that ensures packages compile without Igniter.

- [X] T006 [US4] Rewrite `apps/jido_murmur/lib/mix/tasks/jido_murmur.install.ex` with `if Code.ensure_loaded?(Igniter)` guard: Igniter branch defines `use Igniter` module, else branch defines `use Mix.Task` fallback with clear error message per contracts/install-tasks.md
- [X] T007 [US4] Verify the fallback branch compiles and prints the correct error message when Igniter is absent (can test by temporarily commenting out Igniter dep)

**Checkpoint**: Guard pattern established. Fallback message works. Pattern ready for reuse across all packages.

---

## Phase 3: User Story 1 — Developer Installs jido_murmur with One Command (Priority: P1) 🎯 MVP

**Goal**: Igniter-based `mix jido_murmur.install` generates migrations, adds config, adds supervisor to app tree.

**Independent Test**: Run install against a fresh Phoenix project and verify all expected files/modifications.

### Tests for User Story 1

- [X] T008 [P] [US1] Create `apps/jido_murmur/test/mix/tasks/jido_murmur_install_test.exs` with tests for: migration generation, config block injection, supervisor addition, idempotency (re-run produces no duplicates)

### Implementation for User Story 1

- [X] T009 [US1] Implement Igniter branch of `apps/jido_murmur/lib/mix/tasks/jido_murmur.install.ex`: generate 4 migrations (workspaces, workspace_sessions, messages, workspace_agents) using `Igniter.Project.Module` or `Igniter.copy_template/3`
- [X] T010 [US1] Add config injection to jido_murmur install: use `Igniter.Project.Config.configure/5` to add `:jido_murmur` config block with `repo:`, `pubsub:`, `jido_mod:`, `otp_app:` keys
- [X] T011 [US1] Add supervisor injection to jido_murmur install: use `Igniter.Project.Application.add_new_child/3` to add `JidoMurmur.Supervisor` to the application supervision tree
- [X] T012 [US1] Add idempotency checks: skip config if `:jido_murmur` key already exists, skip migrations if migration files with matching names exist

**Checkpoint**: jido_murmur install works end-to-end. Generates migrations, injects config, adds supervisor. Re-running is idempotent.

---

## Phase 4: User Story 2 — Developer Installs jido_tasks with Dependency Chain (Priority: P1)

**Goal**: `mix jido_tasks.install` detects if jido_murmur is configured and chains its install if needed.

**Independent Test**: Run jido_tasks install on fresh project (no jido_murmur) and verify both get set up.

### Tests for User Story 2

- [X] T013 [P] [US2] Create `apps/jido_tasks/test/mix/tasks/jido_tasks_install_test.exs` with tests for: prerequisite chaining, standalone install (jido_murmur already configured), config block injection, idempotency

### Implementation for User Story 2

- [X] T014 [US2] Rewrite `apps/jido_tasks/lib/mix/tasks/jido_tasks.install.ex` with guard pattern: Igniter branch uses `Igniter.compose_task/3` to chain `jido_murmur.install` when `:jido_murmur` config is absent, else branch shows fallback error
- [X] T015 [US2] Implement jido_tasks Igniter install: generate `create_jido_tasks` migration, add `:jido_tasks` config block with `repo:` and `pubsub:` keys, idempotency checks

**Checkpoint**: jido_tasks install chains prerequisites. Works standalone when jido_murmur already configured. Idempotent.

---

## Phase 5: User Story 3 — Developer Installs jido_murmur_web Components (Priority: P2)

**Goal**: `mix jido_murmur_web.install` copies component files and injects imports.

**Independent Test**: Run install and verify component files created and imports injected.

### Implementation for User Story 3

- [X] T016 [US3] Rewrite `apps/jido_murmur_web/lib/mix/tasks/jido_murmur_web.install.ex` with guard pattern: Igniter branch copies component files to consumer's `lib/{app}_web/components/jido_murmur/` using `Igniter.copy_template/3`, injects import into `{app}_web.ex` html_helpers block, else branch shows fallback error
- [X] T017 [US3] Add idempotency: skip files that already exist, skip import if already present

**Checkpoint**: Component install works. Files copied. Imports injected. Idempotent.

---

## Phase 6: User Story 4 — Developer Uses Igniter-Free Fallback (Priority: P2)

**Goal**: All packages show clear error when Igniter is absent.

**Independent Test**: Remove Igniter from deps and run install commands.

### Implementation for User Story 4

- [X] T018 [P] [US4] Implement fallback branch in `apps/jido_tasks/lib/mix/tasks/jido_tasks.install.ex` (else branch of guard) with error message and remediation instructions
- [X] T019 [P] [US4] Implement fallback branch in `apps/jido_murmur_web/lib/mix/tasks/jido_murmur_web.install.ex` (else branch of guard) with error message
- [X] T020 [P] [US4] Create `apps/jido_artifacts/lib/mix/tasks/jido_artifacts.install.ex` with guard pattern: Igniter branch adds `:jido_artifacts` config block, else branch shows fallback error

**Checkpoint**: All four packages compile without Igniter and show clear error messages.

---

## Phase 7: User Story 5 — Developer Scaffolds Agent Profile (Priority: P3)

**Goal**: `mix jido_murmur.gen.profile Name` creates a new agent profile module.

**Independent Test**: Run generator and verify output module compiles.

### Implementation for User Story 5

- [X] T021 [US5] Create `apps/jido_murmur/lib/mix/tasks/jido_murmur.gen.profile.ex` with guard pattern: Igniter branch generates profile module at `lib/{app}/agents/profiles/{name}.ex` with `use Jido.AI.Agent` boilerplate per contracts/install-tasks.md, else branch shows fallback error
- [X] T022 [US5] Implement profile template with configurable name, default tools (`JidoMurmur.TellAction`), default plugins (`JidoMurmur.StreamingPlugin`, `JidoArtifacts.ArtifactPlugin`), placeholder system_prompt, and `catalog_meta/0`

**Checkpoint**: Profile generator creates compilable module following project conventions.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Integration verification

- [X] T023 Run full umbrella test suite (`mix test`) from repo root — verify all existing tests pass
- [X] T024 Run `mix precommit` from repo root to verify Credo, Dialyxir, and formatting compliance
- [X] T025 Verify all four install tasks work by testing against the murmur_demo app configuration

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — establishes guard pattern
- **US1 jido_murmur (Phase 3)**: Depends on Phase 2 — MVP install task
- **US2 jido_tasks (Phase 4)**: Depends on Phase 3 (chains jido_murmur.install)
- **US3 jido_murmur_web (Phase 5)**: Depends on Phase 2 — can run parallel with US1
- **US4 Fallback (Phase 6)**: Can run parallel with US1/US3 after Phase 2
- **US5 Generator (Phase 7)**: Depends on Phase 2 — can run parallel with US1
- **Polish (Phase 8)**: Depends on all stories complete

### Parallel Opportunities

```
After Phase 2 (guard pattern) completes:
├── Phase 3: US1 (jido_murmur install) — apps/jido_murmur/lib/mix/tasks/
├── Phase 5: US3 (web install) — apps/jido_murmur_web/lib/mix/tasks/
├── Phase 6: US4 (fallbacks) — all packages' else branches
└── Phase 7: US5 (generator) — apps/jido_murmur/lib/mix/tasks/

Then sequentially:
└── Phase 4: US2 (jido_tasks) — depends on US1
└── Phase 8: Polish
```

---

## Implementation Strategy

### MVP First (US1 only)

1. Complete Phase 1: Setup (add deps)
2. Complete Phase 2: Guard pattern established
3. Complete Phase 3: jido_murmur install works
4. **STOP and VALIDATE**: Developer can set up jido_murmur with one command

### Incremental Delivery

1. Setup + Guard pattern → Foundation ready
2. Add jido_murmur install (US1) → Primary install works (MVP)
3. Add jido_tasks install (US2) → Chaining works
4. Add web install (US3) → Component setup automated
5. Add fallbacks (US4) → Graceful degradation complete
6. Add generator (US5) → Profile scaffolding available

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story from spec.md
- US4 (fallback) spans all packages but is treated as a parallel concern
- The jido_artifacts install task (T020) assumes spec 003 has been implemented
- Commit after each phase checkpoint
