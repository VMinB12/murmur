# Tasks: Data Contract Enforcement

**Input**: Design documents from `/specs/tickets/009-data-contract-enforcement/`
**Prerequisites**: `plan.md` (required), `Spec.md` (required), `Research.md`, `Decisions.md`

**Tests**: Included. The ticket acceptance criteria require artifact integration coverage, checkpoint round-trip verification, and a clean manual Dialyzer run.

**Organization**: Tasks are grouped by user story priority. P1 artifact contract work comes first because it removes the current production bug class and establishes the shared pattern used by later P2/P3 work.

## Phase 1: P1 Artifact Contract Foundations

- [x] T001 Create `apps/jido_artifacts/lib/jido_artifacts/envelope.ex` defining `%JidoArtifacts.Envelope{}` with `@enforce_keys [:data, :version, :source, :updated_at]`, `@type t`, and public constructor/accessor helpers.
- [x] T002 Update `apps/jido_artifacts/lib/jido_artifacts/actions/store_artifact.ex` so `StoreArtifact.run/2` always persists `%JidoArtifacts.Envelope{}` and deletes keys on nil merge results without leaving map-based legacy code.
- [x] T003 Update `apps/jido_artifacts/lib/jido_artifacts/artifact_plugin.ex` so the broadcast payload and override params carry the canonical `%JidoArtifacts.Envelope{}` generated for that artifact update.
- [x] T004 Update `apps/jido_artifacts/lib/jido_artifacts/artifact.ex` so merge callbacks operate on existing envelope payloads instead of envelope structs, and add/refresh the public `@spec` annotations on the artifact API.
- [x] T005 Update `apps/murmur_demo/lib/murmur_web/live/workspace_live.ex` so live artifact signals store `%JidoArtifacts.Envelope{}` in `socket.assigns.artifacts`, artifact deletion mirrors persistence semantics, and SQL result re-execution mutates the envelope payload instead of reverting to a raw map.
- [x] T006 Update `apps/murmur_demo/lib/murmur_web/components/artifacts.ex` to require `%JidoArtifacts.Envelope{}` at the boundary and remove the legacy `unwrap_envelope/1` fallback clauses.
- [x] T007 [P] Update `apps/jido_murmur_web/lib/jido_murmur_web/components/artifact_panel.ex` to require `%JidoArtifacts.Envelope{}` at the boundary and remove the legacy unwrap fallback clauses.
- [x] T008 [P] Update `apps/jido_murmur_web/priv/templates/components/artifact_panel.ex` and `apps/jido_murmur_web/mix.exs` so the generated component template and published package both depend on and use `JidoArtifacts.Envelope` directly.

## Phase 2: P1 Artifact Contract Verification

- [x] T009 Update `apps/jido_artifacts/test/jido_artifacts/actions/store_artifact_test.exs` and `apps/murmur_demo/test/murmur/agents/actions/store_artifact_test.exs` to assert `%JidoArtifacts.Envelope{}` construction, version increments, and delete behavior.
- [x] T010 Update `apps/jido_artifacts/test/jido_artifacts/artifact_test.exs` and `apps/murmur_demo/test/murmur/agents/artifact_plugin_test.exs` to verify merge behavior against existing envelopes and to assert that plugin-broadcast artifact signals carry `%JidoArtifacts.Envelope{}`.
- [x] T011 Update `apps/jido_murmur_web/test/jido_murmur_web/components/artifact_panel_test.exs` so dispatcher-level component tests pass `%JidoArtifacts.Envelope{}` into the panel and badge/detail entry points.
- [x] T012 Update `apps/murmur_demo/test/murmur_web/live/workspace_live_artifact_persistence_test.exs` so checkpoint round-trip tests seed `%JidoArtifacts.Envelope{}` artifacts and verify thaw preserves the struct with no conversion path.
- [x] T013 Add `apps/murmur_demo/test/murmur_web/live/workspace_live_artifact_signal_test.exs` covering the signal-driven live path from artifact PubSub broadcast to rendered badge/detail output for the shipped artifact types, including badge counts and visible content.

## Phase 3: P2 Typed SQL Result Boundary

- [x] T014 Create `apps/jido_sql/lib/jido_sql/query_result.ex` defining `%JidoSql.QueryResult{}` with enforced keys and a public `@type t` for query execution results.
- [x] T015 Update `apps/jido_sql/lib/jido_sql/query_executor.ex` so `execute/3` returns `{:ok, %JidoSql.QueryResult{}} | {:error, reason}`, and adjust helper functions only as needed to keep the public boundary coherent.
- [x] T016 Update `apps/jido_sql/lib/jido_sql/tools/query.ex`, `apps/jido_sql/lib/jido_sql/tools/display.ex`, and `apps/murmur_demo/lib/murmur_web/live/workspace_live.ex` to pattern-match on `%JidoSql.QueryResult{}` instead of plain maps.
- [x] T017 Update `apps/jido_sql/test/jido_sql/query_executor_test.exs`, `apps/jido_sql/test/jido_sql/tools/query_test.exs`, and `apps/jido_sql/test/jido_sql/tools/display_test.exs` to assert the typed `%JidoSql.QueryResult{}` contract.

## Phase 4: P2 Public Specs and Manual Dialyzer

- [ ] T018 Add public `@spec` annotations to `apps/jido_artifacts/lib/jido_artifacts/envelope.ex` and `apps/jido_artifacts/lib/jido_artifacts/artifact.ex`.
- [ ] T019 [P] Add public `@spec` annotations to `apps/jido_sql/lib/jido_sql/query_executor.ex`, `apps/jido_murmur/lib/jido_murmur/runner.ex`, and `apps/jido_murmur/lib/jido_murmur/ui_turn.ex`.
- [ ] T020 [P] Add public `@spec` annotations to `apps/jido_tasks/lib/jido_tasks/tasks.ex` and `apps/jido_murmur/lib/jido_murmur/storage/ecto.ex`.
- [ ] T021 Confirm the root `mix.exs` keeps `mix precommit` unchanged, then run `mix dialyzer` manually from the repo root and create `.dialyzer_ignore.exs` only if a warning is verified to be a false positive.

## Phase 5: P3 Signal Schema Tightening

- [ ] T022 Update `apps/jido_murmur/lib/jido_murmur/signals/message_received.ex` and `apps/jido_murmur/lib/jido_murmur/signals/message_completed.ex` so their schemas use concrete field types rather than `:any` where the current payload shape is known.
- [ ] T023 Update `apps/jido_tasks/lib/jido_tasks/signals/task_created.ex` and `apps/jido_tasks/lib/jido_tasks/signals/task_updated.ex` so their `task` fields use `JidoTasks.Task.t()` rather than `:any`.
- [ ] T024 Add a typed artifact signal module or equivalent typed schema implementation under `apps/jido_artifacts/lib/jido_artifacts/` so the `artifact.*` family documents a concrete Murmur-owned payload contract without requiring a Jido framework change.
- [ ] T025 Update the corresponding signal tests in `apps/jido_murmur/test/jido_murmur/signals/*.exs` and `apps/jido_tasks/test/jido_tasks/signals/*.exs`, and add artifact signal tests under `apps/jido_artifacts/test/jido_artifacts/`, to assert the tightened schema contracts.

## Phase 6: End-to-End Validation

- [ ] T026 Run focused tests for `apps/jido_artifacts/test/`, `apps/jido_sql/test/`, `apps/jido_murmur_web/test/jido_murmur_web/components/artifact_panel_test.exs`, and the Murmur artifact LiveView tests to verify the new contracts before full-suite validation.
- [ ] T027 Run `mix test` from `/Users/vincent.min/Projects/murmur` after the P1 and P2 work is complete.
- [ ] T028 Run `mix precommit` from `/Users/vincent.min/Projects/murmur` once implementation and manual Dialyzer verification are complete.