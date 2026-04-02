# Journal: Data Contract Enforcement

## 2026-04-01

- Resumed ticket from `research` status. Research.md was already complete with a prioritized action plan.
- Performed codebase exploration to validate research findings against current code:
  - Confirmed: zero `@enforce_keys` usage across the entire codebase
  - Confirmed: `unwrap_envelope/1` fallback pattern exists in both `artifact_panel.ex` and `artifacts.ex`
  - Confirmed: `workspace_live` stores raw artifact data (not enveloped) on the live path
  - Confirmed: ~15-20% typespec coverage on public APIs at inter-module boundaries
  - Confirmed: Dialyzer is a dependency but not in the precommit alias
- Drafted Spec.md with 7 user stories across 3 priority tiers (P1: envelope + unified path + integration tests, P2: SQL struct + Dialyzer + typespecs, P3: signal typing).
- Created Decisions.md with 5 open questions: persisted artifact migration strategy, struct serialization, Dialyzer strictness, TypedStruct vs plain Elixir, and signal typing scope.
- Status moved to `open-questions` — awaiting user decisions on Q1–Q5 before proceeding to Plan phase.

## 2026-04-02

- Resumed ticket after the spec and decisions were settled, with the user explicitly requesting the planning artifacts before code changes.
- Reviewed the current implementation points for `StoreArtifact`, `ArtifactPlugin`, `workspace_live`, artifact component dispatchers, checkpoint persistence, and `JidoSql.QueryExecutor` to make the plan concrete rather than aspirational.
- Created `plan.md` with a hard-cutover strategy: canonical `%JidoArtifacts.Envelope{}` boundary first, then artifact integration tests, then typed SQL results, then public specs + manual Dialyzer, then signal schema tightening.
- Created `tasks.md` with phased work items covering the artifact contract, integration coverage, SQL result struct, `@spec` coverage, manual Dialyzer verification, and signal typing.
- Updated ticket status to `planned` so the folder state now matches the available spec, decisions, plan, and task breakdown.
- Started implementation on Phase 1 and introduced `JidoArtifacts.Envelope` as the canonical in-memory artifact contract.
- Updated `StoreArtifact`, `ArtifactPlugin`, `Artifact.emit/4`, `workspace_live`, the demo artifact dispatcher, and the shared `jido_murmur_web` artifact panel so the live path now carries the same envelope shape as persisted checkpoints.
- Updated the most directly impacted unit/component tests to use `%Envelope{}` and verified the envelope refactor with `mix compile`, app-local `jido_artifacts` tests, and app-local `jido_murmur_web` component tests.
- Attempted a root-level focused test run, but the workspace test alias currently aborts before execution because `JidoSql.Repo` cannot connect to PostgreSQL on `localhost:5432`. That environment issue is separate from the Phase 1 refactor.
- Continued with Phase 2 by expanding the contract-focused tests rather than adding more compatibility code.
- Fixed `workspace_live.html.heex` so split and unified badge rows filter artifact visibility using the `%Envelope{}` payload instead of legacy raw-list/raw-map checks.
- Expanded artifact verification coverage with stronger plugin merge assertions and a new `workspace_live_artifact_signal_test.exs` module covering live signal-driven rendering for `papers`, `displayed_paper`, and `sql_results` artifacts.
- Verified the new Phase 2 changes compile cleanly with `mix compile`, but Murmur demo DB-backed test execution remains blocked in this environment because PostgreSQL is not available on `localhost:5432` for `JidoSql.Repo` setup.
- Implemented Phase 3 by introducing `%JidoSql.QueryResult{}` as the canonical `QueryExecutor.execute/3` return type and updating the SQL tools, SQL result renderer, and `workspace_live` re-execution path to consume the struct explicitly.
- Added a small `JidoSql.query_executor/0` injection point so SQL tools can be tested without a live database, keeping the production default on `JidoSql.QueryExecutor`.
- Added direct `jido_sql` tests for `QueryResult`, `QueryExecutor` helper behavior, and SQL tool behavior using fake executors, then verified them with `mix test --no-start` from `apps/jido_sql`.
- Completed Phase 4 by filling in the missing public `@spec` coverage on `JidoMurmur.Runner`, `JidoTasks.Tasks`, `JidoTasks.Task`, and `JidoMurmur.Storage.Ecto`, while tightening `JidoSql.QueryExecutor` helper result types and adding the missing public spec on `JidoArtifacts.Artifact.artifact_topic/2`.
- Reconfirmed that the umbrella `mix precommit` alias remains unchanged and does not include Dialyzer.
- Ran `mix dialyzer` manually from the repository root; it passed with zero errors, so no `.dialyzer_ignore.exs` file was needed.
