# Implementation Plan: SQL Agent Plugin

**Branch**: `008-sql-agent-plugin` | **Date**: 2026-03-31 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/008-sql-agent-plugin/spec.md`

## Summary

Add a SQL agent plugin that lets users ask natural-language questions about any SQL database. The agent connects to a separate, independently configured database, reads its schema at startup, and provides two tools: `query` (exploratory, truncated results for the LLM) and `display` (full paginated results for the user). SQL query text is persisted in thread entries for lazy re-execution on revisit.

## Technical Context

**Language/Version**: Elixir ≥ 1.15 on OTP
**Primary Dependencies**: Jido 2.0 (agent framework), Jido.AI (LLM), Ecto SQL + Postgrex (database), Phoenix LiveView 1.1
**Storage**: PostgreSQL via Ecto for both the app database (Murmur.Repo) and a separate SQL agent target database (JidoSql.Repo)
**Testing**: ExUnit with Phoenix.LiveViewTest and LazyHTML
**Target Platform**: Phoenix web application (server-side)
**Project Type**: Umbrella app — new code spans `apps/jido_sql` (tools, schema introspection, repo) and `apps/murmur_demo` (agent profile, config)
**Performance Goals**: Query tool response < 15s (timeout), schema introspection < 5s at startup
**Constraints**: Query tool results truncated to 50 rows / 20 columns by default; display tool results paginated
**Scale/Scope**: Single SQL agent profile; one dedicated Repo connection pool; conversation persistence via existing ThreadEntry

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Code Quality | ✅ PASS | Single-responsibility modules: Repo, Schema introspection, Query tool, Display tool, Agent profile. No business logic in LiveViews. |
| II. Testing Standards | ✅ PASS | Tools testable via ExUnit with SQL.Sandbox. Agent profile testable. Thread entry persistence testable. |
| III. UX Consistency | ✅ PASS | Forms use `<.input>`, icons use `<.icon>`, collections use streams, Tailwind only. Paginated table follows existing patterns. |
| IV. Performance | ✅ PASS | Schema read once at startup. Query timeout enforced. Truncation prevents memory bloat. Lazy re-execution on revisit. |
| V. Developer Experience | ✅ PASS | `mix setup` handles migration. Separate database URI documented in README. No extra services beyond PostgreSQL. |
| Technology Constraints | ✅ PASS | Elixir/Phoenix/Ecto/Tailwind/Req/Jido — all existing stack. No new frameworks. |
| Development Workflow | ✅ PASS | `mix precommit` covers all checks. Migration via `mix ecto.gen.migration`. |

**Pre-Phase 0 Gate: PASS** — No violations. Proceeding to research.

## Project Structure

### Documentation (this feature)

```text
specs/008-sql-agent-plugin/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
apps/jido_sql/
├── mix.exs
├── lib/
│   ├── jido_sql.ex                    # Public API module
│   ├── jido_sql/
│   │   ├── repo.ex                    # Ecto Repo for target database
│   │   ├── schema_introspection.ex    # Reads tables/columns at startup
│   │   └── query_executor.ex          # Raw SQL execution with truncation
│   └── jido_sql/tools/
│       ├── query.ex                   # Jido.Action — exploratory query tool
│       └── display.ex                 # Jido.Action — display results tool
└── test/
    ├── jido_sql/
    │   ├── schema_introspection_test.exs
    │   └── query_executor_test.exs
    └── jido_sql/tools/
        ├── query_test.exs
        └── display_test.exs

apps/murmur_demo/
├── lib/murmur/agents/profiles/
│   └── sql_agent.ex                   # Agent profile definition
└── priv/repo/migrations/
    └── (none — JidoSql.Repo has no migrations on the target DB)

config/
├── config.exs                         # Add JidoSql.Repo config, SqlAgent profile
├── dev.exs                            # Dev database URL for SQL agent
├── runtime.exs                        # Runtime SQL_AGENT_DATABASE_URL
└── test.exs                           # Test database for SQL agent
```

**Structure Decision**: Follows existing umbrella pattern. `jido_sql` is a self-contained app with its own Repo, tools, and schema introspection. Agent profile lives in `murmur_demo` alongside other profiles. No new Phoenix routes needed — display results flow through existing artifact/PubSub infrastructure.

## Post-Design Constitution Re-Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Code Quality | ✅ PASS | 6 modules, each single-responsibility. No business logic in LiveViews. Artifact pattern reused. |
| II. Testing Standards | ✅ PASS | QueryExecutor and SchemaIntrospection testable with SQL.Sandbox. Tools testable via Jido.Action test patterns. |
| III. UX Consistency | ✅ PASS | Paginated table uses Tailwind. Placeholder/click pattern consistent with existing artifact display. |
| IV. Performance | ✅ PASS | Schema cached in `:persistent_term`. Truncation enforced. Lazy re-execution avoids loading all queries. |
| V. Developer Experience | ✅ PASS | Single env var (`SQL_AGENT_DATABASE_URL`) to configure. Quickstart documented. No extra services. |
| Technology Constraints | ✅ PASS | No new deps required. Postgrex already in umbrella via Ecto SQL. |
| Development Workflow | ✅ PASS | All new code covered by `mix precommit`. No special setup steps. |

**Post-Design Gate: PASS** — No violations introduced during design phase.
