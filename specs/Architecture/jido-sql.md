# jido_sql — SQL Agent Plugin

## Purpose

Natural-language-to-SQL agent plugin for the Jido framework. Enables agents to translate user questions into SQL queries, execute them against a target database, and display results — with built-in safety guardrails for read-only access.

## Public API

### Agent Tools

| Tool | Action Name | Purpose |
|------|-------------|---------|
| `Query` | `sql_query` | Execute SQL and return truncated text preview for LLM reasoning |
| `Display` | `sql_display` | Execute SQL and emit deferred artifact for full paginated display |

### Schema Introspection (JidoSql.SchemaIntrospection)

| Function | Purpose |
|----------|---------|
| `describe_schema/1` | Read public schema from DB, return human-readable text |
| `cache_schema/1` | Cache schema into `:persistent_term` at startup |
| `cached_schema/0` | Retrieve cached schema text (zero-cost reads) |

### Query Executor (JidoSql.QueryExecutor)

| Function | Purpose |
|----------|---------|
| `execute/3` | Execute raw SQL with timeout (default 15s), sanitize results |
| `truncate/3` | Limit to max_rows/max_columns, set truncated flag |
| `format_text_table/1` | Format as pipe-separated text table for LLM |

## Internal Architecture

```
Agent Request
    ↓
RequestTransformer (injects cached schema from :persistent_term)
    ↓
LLM generates SQL
    ↓
sql_query (exploration)          sql_display (presentation)
    ↓                                ↓
QueryExecutor.execute/3          QueryExecutor.execute/3
    ↓                                ↓
truncate → format_text_table     emit artifact for UI rendering
    ↓                                ↓
Return text to LLM               Artifact visible in data panel
```

### Application Startup

1. Checks for `SQL_AGENT_DATABASE_URL` environment variable
2. If set, starts `JidoSql.Repo` and loads schema into `:persistent_term`
3. Schema is injected into every LLM request via `RequestTransformer`

## Safety Guardrails

- **Read-only connection:** PostgreSQL parameter `default_transaction_read_only: "on"` enforced at DB level
- **Query timeout:** 15 seconds per query (configurable)
- **Separate connection:** Uses its own Ecto Repo, not the main app's
- **Result truncation:** `max_rows` and `max_columns` prevent memory bloat
- **Schema-only introspection:** Reads only `information_schema.columns` from `public` schema

## Data Models

### Query Result

```elixir
%{
  columns: [String.t()],
  rows: [[String.t()]],
  total_rows: non_neg_integer(),
  total_columns: non_neg_integer(),
  truncated: boolean()
}
```

### SQL Display Artifact

```elixir
%{
  sql: String.t(),
  label: String.t(),            # first 80 chars of query
  row_count: non_neg_integer(),
  column_count: non_neg_integer()
}
```

## Dependencies

**Requires:** `jido ~> 2.0`, `jido_ai ~> 2.0`, `jido_action ~> 2.0`, `jido_artifacts` (umbrella), `jido_murmur` (umbrella), `ecto_sql ~> 3.0`, `postgrex`, `jason ~> 1.0`

**Used by:** `murmur_demo` (SqlAgent profile)

## Configuration

```elixir
config :jido_sql,
  ecto_repos: [JidoSql.Repo],
  repo: JidoSql.Repo,
  max_rows: 50,
  max_columns: 20
```

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SQL_AGENT_DATABASE_URL` | — | Connection string for target database |
| `SQL_AGENT_POOL_SIZE` | `5` | Connection pool size |
| `SQL_AGENT_READ_ONLY` | `"on"` | Force read-only transactions |
