# Tasks: SQL Agent Plugin

**Input**: Design documents from `/specs/008-sql-agent-plugin/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/tools.md, quickstart.md

**Tests**: Not explicitly requested in the feature specification. Tests are omitted.

**Organization**: Tasks grouped by user story. US2 (Schema Awareness) is foundational and precedes US1 (Ask Questions). US3/US4 enhance the core tools. US6 adds persistence. US5 is documentation-only.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Create the `jido_sql` umbrella app skeleton, Repo, and configuration

- [X] T001 Create `apps/jido_sql/mix.exs` declaring deps: `{:ecto_sql, "~> 3.0"}, {:postgrex, "~> 0.19"}, {:jido, in_umbrella: true}, {:jido_action, in_umbrella: true}, {:jido_artifacts, in_umbrella: true}`
- [X] T002 Create `apps/jido_sql/lib/jido_sql.ex` top-level module with `repo/0` config accessor reading from `:jido_sql, :repo`
- [X] T003 [P] Create `apps/jido_sql/lib/jido_sql/repo.ex` defining `JidoSql.Repo` with `use Ecto.Repo, otp_app: :jido_sql, adapter: Ecto.Adapters.Postgres`
- [X] T004 Add `config :jido_sql, repo: JidoSql.Repo` and `JidoSql.Repo` database config to `config/config.exs`, `config/dev.exs`, `config/test.exs`, and `config/runtime.exs` (using `SQL_AGENT_DATABASE_URL` env var)
- [X] T005 Add `JidoSql.Repo` to the application supervision tree in `apps/jido_sql/lib/jido_sql/application.ex`
- [X] T006 [P] Create `apps/jido_sql/test/test_helper.exs` with ExUnit configuration and Ecto sandbox setup for `JidoSql.Repo`
- [X] T007 Verify umbrella compiles: run `mix compile` from repo root with zero errors

---

## Phase 2: Foundational — Query Executor (Blocking Prerequisite)

**Purpose**: Shared SQL execution and truncation logic used by both tools. MUST complete before any user story.

**⚠️ CRITICAL**: Both tools and schema introspection depend on the query executor.

- [X] T008 Create `apps/jido_sql/lib/jido_sql/query_executor.ex` with `execute/3` function: accepts `(repo, sql, opts)`, calls `Ecto.Adapters.SQL.query/4` with configurable timeout (default 15_000ms), returns `{:ok, %{columns: [...], rows: [[...]], total_rows: n}}` or `{:error, "message"}` per contracts/tools.md
- [X] T009 Add `truncate/3` function to `apps/jido_sql/lib/jido_sql/query_executor.ex`: accepts `(result, max_rows \\ 50, max_cols \\ 20)`, slices rows and columns, returns `%{columns: [...], rows: [[...]], truncated: bool, total_rows: n, total_columns: n}`
- [X] T010 Add `format_text_table/1` function to `apps/jido_sql/lib/jido_sql/query_executor.ex`: accepts truncated result, formats as pipe-separated text table with truncation indicator and row count summary

**Checkpoint**: Query execution, truncation, and formatting available for tools and schema introspection.

---

## Phase 3: User Story 2 — Agent Knows the Database Schema (Priority: P1) 🎯 MVP

**Goal**: SQL agent reads database schema at startup and injects it into every LLM request.

**Independent Test**: Start the agent and verify its instructions contain the connected database schema.

- [X] T011 [US2] Create `apps/jido_sql/lib/jido_sql/schema_introspection.ex` with `describe_schema/1` function: accepts repo, queries `information_schema.columns WHERE table_schema = 'public'`, groups by table, returns `{:ok, schema_text}` or `{:error, reason}` per research.md R3
- [X] T012 [US2] Add `describe_schema!/1` raising variant and `cache_schema/1` function to `apps/jido_sql/lib/jido_sql/schema_introspection.ex` that calls `describe_schema!/1` and stores result in `:persistent_term` under `{JidoSql, :schema}`
- [X] T013 [US2] Call `SchemaIntrospection.cache_schema/1` from `apps/jido_sql/lib/jido_sql/application.ex` after Repo starts, logging table/column counts on success and raising on failure
- [X] T014 [US2] Create `apps/jido_sql/lib/jido_sql/request_transformer.ex` implementing `Jido.AI.Reasoning.ReAct.RequestTransformer` behaviour: reads schema from `:persistent_term`, appends `"\n\nDatabase Schema:\n" <> schema_text` to the system message in `transform_request/4`
- [X] T015 [US2] Create `apps/murmur_demo/lib/murmur/agents/profiles/sql_agent.ex` with `use Jido.AI.Agent`: name `"sql_agent"`, description, model `:fast`, tools `[JidoSql.Tools.Query, JidoSql.Tools.Display]`, plugins `[JidoMurmur.StreamingPlugin, JidoArtifacts.ArtifactPlugin]`, `request_transformer: JidoSql.RequestTransformer`, system prompt describing SQL assistant role
- [X] T016 [US2] Register `Murmur.Agents.Profiles.SqlAgent` in `config/config.exs` under `:jido_murmur, :profiles` list

**Checkpoint**: SQL agent starts, reads schema, and includes it in every LLM request. Agent visible in catalog.

---

## Phase 4: User Story 1 — Ask a Question About the Database (Priority: P1) 🎯 MVP

**Goal**: User can ask natural-language questions, agent generates SQL, executes it, and shows results.

**Independent Test**: Send a chat message to the SQL agent and verify a query result table is displayed.

- [X] T017 [US1] Create `apps/jido_sql/lib/jido_sql/tools/query.ex` with `use Jido.Action, name: "sql_query", schema: [sql_query: [type: :string, required: true]]`: calls `QueryExecutor.execute/3` then `truncate/3` then `format_text_table/1`, returns `{:ok, %{result: formatted_text}}` or `{:error, message}` per contracts/tools.md
- [X] T018 [US1] Create `apps/jido_sql/lib/jido_sql/tools/display.ex` with `use Jido.Action, name: "sql_display", schema: [sql_query: [type: :string, required: true]]`: calls `QueryExecutor.execute/3` to validate the SQL works, then emits a deferred artifact via `Artifact.emit(ctx, "sql_results", %{sql: ..., label: ..., row_count: ..., column_count: ...}, mode: :merge, merge: {:append, :data})`, returns `{:ok, %{result: "Query result displayed to user (N rows)"}, directive}` or `{:error, message}` per contracts/tools.md

**Checkpoint**: Both tools functional. Agent can query the database and display results to the user. Core value proposition works.

---

## Phase 5: User Story 3 — Query Results Are Truncated (Priority: P2)

**Goal**: The `query` tool caps results to prevent context window overflow.

**Independent Test**: Execute a query returning thousands of rows and verify the tool result is truncated.

*Note: Truncation logic is already implemented in T009/T010 (Phase 2). This phase ensures it's properly wired into the query tool.*

- [X] T019 [US3] Verify `apps/jido_sql/lib/jido_sql/tools/query.ex` calls `truncate/3` with configurable limits read from application config (`:jido_sql, :max_rows` and `:jido_sql, :max_columns`), defaulting to 50 rows / 20 columns
- [X] T020 [US3] Add truncation defaults to `config/config.exs`: `config :jido_sql, max_rows: 50, max_columns: 20`

**Checkpoint**: Query tool enforces configurable truncation limits.

---

## Phase 6: User Story 4 — User Sees Full Display Results (Priority: P2)

**Goal**: The data panel renderer dynamically executes SQL and shows paginated results in tabs.

**Independent Test**: Call display tool and verify the data panel shows a new tab with paginated query results.

- [X] T021 [US4] Create SQL result artifact renderer component in `apps/jido_murmur_web/` that renders `"sql_results"` artifacts: shows sub-tabs (one per displayed query, labeled from artifact `label` field), dynamically executes SQL via `QueryExecutor.execute/2` when a tab is viewed, renders paginated HTML table with Tailwind styling (column headers, row data, page navigation at 100 rows/page, empty state with headers)
- [X] T022 [US4] Register the SQL result renderer in the artifact renderer registry in `config/config.exs` under `:jido_murmur, :artifact_renderers` mapping `"sql_results"` to the renderer component

**Checkpoint**: Display tool results appear as paginated tables in data panel tabs. Each display call creates a new sub-tab.

---

## Phase 7: User Story 6 — Persistent Conversation and Query History (Priority: P2)

**Goal**: Two-layer persistence: ThreadEntry drives chat column, artifacts drive data panel tabs on revisit.

**Independent Test**: Have a conversation, restart server, reopen conversation, verify chat history visible and data panel tabs reappear with re-executable queries.

- [X] T023 [US6] Ensure both `query.ex` and `display.ex` tools in `apps/jido_sql/lib/jido_sql/tools/` include `sql` and `tool_name` fields in their return payload so they are persisted in `ThreadEntry.payload` by the existing storage adapter (drives chat column)
- [X] T024 [US6] Verify `display.ex` artifact emission uses `:merge` mode with append so successive display calls accumulate in `agent.state[:artifacts]["sql_results"]` and survive hibernation via checkpoint (drives data panel)
- [X] T025 [US6] Update the SQL result artifact renderer (from T021) to show "Click to load results" placeholder for each sub-tab when artifacts are restored from checkpoint on revisit, triggering `"reexecute_query"` event on click
- [X] T026 [US6] Add `"reexecute_query"` event handler to the data panel LiveView: receives `%{"sql" => sql_text, "index" => n}`, calls `JidoSql.QueryExecutor.execute/3`, renders paginated results in the corresponding data panel tab. On error, display error message in place of the result table.

**Checkpoint**: Past conversations show query history. Users can click to re-execute and see current results. Errors handled gracefully.

---

## Phase 8: User Story 5 — Read-Only Database Access (Priority: P3)

**Goal**: Documentation explains how to configure read-only PostgreSQL connections.

**Independent Test**: Follow the docs and verify write queries are rejected.

- [X] T027 [US5] Add read-only configuration section to `apps/jido_sql/README.md` documenting both approaches: (1) create read-only PostgreSQL user with GRANT SELECT, (2) connection URI with `options=-c default_transaction_read_only=on` per quickstart.md

**Checkpoint**: Read-only documentation complete. Operators can secure the SQL agent connection.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Integration verification, configuration cleanup, and final validation

- [X] T028 [P] Add `@moduledoc` to all new modules in `apps/jido_sql/lib/` describing purpose and usage
- [X] T029 Verify `JidoSql.Repo` starts correctly with `SQL_AGENT_DATABASE_URL` not set: should log a clear error and not crash the application (graceful degradation — SQL agent simply not available)
- [X] T030 Run full umbrella test suite (`mix test`) from repo root — verify all existing tests pass with zero regressions
- [X] T031 Run `mix precommit` from repo root to verify Credo, Dialyxir, and formatting compliance

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories
- **US2 Schema (Phase 3)**: Depends on Phase 2
- **US1 Ask Questions (Phase 4)**: Depends on Phase 2 + Phase 3 (needs schema + executor)
- **US3 Truncation (Phase 5)**: Depends on Phase 4 (wiring only — logic in Phase 2)
- **US4 Display (Phase 6)**: Depends on Phase 4 (needs display tool)
- **US6 Persistence (Phase 7)**: Depends on Phase 4 + Phase 6 (needs tools + renderer + artifact pipeline)
- **US5 Read-Only Docs (Phase 8)**: No code deps — can run parallel after Phase 1
- **Polish (Phase 9)**: Depends on all phases complete

### Parallel Opportunities

```
After Phase 2 (executor) completes:
├── Phase 3: US2 (Schema) — schema_introspection.ex, request_transformer.ex, sql_agent.ex
└── Phase 8: US5 (Read-Only Docs) — README.md only, no code deps

After Phase 3 (schema) completes:
└── Phase 4: US1 (Tools) — query.ex, display.ex

After Phase 4 (tools) completes:
├── Phase 5: US3 (Truncation config) — config tweaks only
├── Phase 6: US4 (Display renderer) — data panel component with dynamic SQL execution
└── Phase 7: US6 (Persistence) — ThreadEntry payload wiring + artifact revisit placeholders

Then sequentially:
└── Phase 9: Polish
```

### Suggested MVP Scope

**Phases 1–4** deliver the complete MVP:
1. Setup → App skeleton, Repo, config
2. Foundational → Query executor with truncation
3. US2 → Schema introspection + agent profile
4. US1 → Query and display tools

At this point the user can ask questions and see results. Everything after is enhancement.

---

## Implementation Strategy

### MVP First (Phases 1–4)

1. Setup (Phase 1) — app skeleton, repo, config
2. Query Executor (Phase 2) — shared execution + truncation
3. Schema Awareness (Phase 3) — introspection + request transformer + agent profile
4. Ask Questions (Phase 4) — query and display tools
5. **STOP and VALIDATE**: SQL agent functional end-to-end

### Incremental Delivery

1. Setup + Executor → Infrastructure ready
2. Add Schema (US2) → Agent knows the database
3. Add Tools (US1) → Core Q&A works
4. Add Truncation config (US3) → Reliability for large tables
5. Add Display renderer (US4) → Data panel tabs with dynamic SQL execution
6. Add Persistence (US6) → Chat history + data panel tabs survive restarts
7. Add Read-Only docs (US5) → Production safety guidance
8. Each story adds value without breaking previous stories
