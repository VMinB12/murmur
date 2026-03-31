# Research: SQL Agent Plugin

**Feature**: 008-sql-agent-plugin
**Date**: 2026-03-31
**Status**: Complete

## R1: Database Connection Strategy

**Decision**: Use a dedicated `JidoSql.Repo` (Ecto Repo) pointing at a separate database, configured via `SQL_AGENT_DATABASE_URL` environment variable.

**Rationale**: Isolates agent queries from internal application tables (workspaces, sessions, checkpoints). Follows the same pattern as `Murmur.Repo` — just a second Repo in the umbrella. Ecto's `Repo` abstraction handles connection pooling, timeouts, and transactions out of the box.

**Alternatives considered**:
- **Shared Murmur.Repo**: Rejected — exposes internal tables to the LLM and creates security/performance concerns.
- **Raw Postgrex without Ecto**: Rejected — Ecto provides connection pooling, sandboxed testing, and a familiar API. No benefit to going lower-level.
- **Dynamic Repo per session**: Rejected — over-engineered for a single-database-per-deployment model. Can be revisited if multi-tenant DB support is needed later.

## R2: Raw SQL Execution & Truncation

**Decision**: Use `Ecto.Adapters.SQL.query/4` for raw SQL execution. Truncation handled in Elixir by slicing the returned `%Postgrex.Result{columns, rows}`.

**Rationale**: `Ecto.Adapters.SQL.query/4` returns `{:ok, %Postgrex.Result{columns: [String.t()], rows: [[term()]]}}` — a clean structure for both truncation and display. Adding `LIMIT` at the SQL level is unreliable (LLM queries vary), so we truncate in Elixir after execution. This mirrors the Python reference where DuckDB's `.show()` handles truncation.

**Implementation sketch**:
```elixir
def execute(repo, sql, opts \\ []) do
  timeout = Keyword.get(opts, :timeout, 15_000)
  case Ecto.Adapters.SQL.query(repo, sql, [], timeout: timeout) do
    {:ok, %{columns: cols, rows: rows, num_rows: count}} ->
      {:ok, %{columns: cols, rows: rows, total_rows: count}}
    {:error, %Postgrex.Error{} = err} ->
      {:error, Exception.message(err)}
    {:error, err} ->
      {:error, Exception.message(err)}
  end
end

def truncate(result, max_rows \\ 50, max_cols \\ 20) do
  cols = Enum.take(result.columns, max_cols)
  rows = result.rows |> Enum.take(max_rows) |> Enum.map(&Enum.take(&1, max_cols))
  truncated = length(result.rows) > max_rows or length(result.columns) > max_cols
  %{columns: cols, rows: rows, truncated: truncated,
    total_rows: result.total_rows, total_columns: length(result.columns)}
end
```

**Alternatives considered**:
- **SQL-level LIMIT injection**: Rejected — fragile (breaks CTEs, subqueries); LLM should control its own LIMIT.
- **DuckDB via NIF**: Rejected — adds a native dependency; Postgrex is already available and lighter.

## R3: Schema Introspection

**Decision**: Query `information_schema.columns` at startup to build a text summary. Use PostgreSQL-specific `pg_tables` for table listing and `information_schema.columns` for column details (this is the SQL standard and works across most databases).

**Rationale**: `information_schema` is defined by the SQL standard and available in PostgreSQL, MySQL, SQL Server, and others. Using it keeps the feature database-agnostic where possible. The query runs once at startup, so performance is not a concern.

**Implementation sketch**:
```elixir
def describe_schema(repo) do
  {:ok, result} = Ecto.Adapters.SQL.query(repo, """
    SELECT table_name, column_name, data_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
    ORDER BY table_name, ordinal_position
  """, [])

  result.rows
  |> Enum.group_by(&Enum.at(&1, 0))
  |> Enum.map_join("\n\n", fn {table, cols} ->
    columns = Enum.map_join(cols, "\n", fn [_, col, type] ->
      "  - #{col} (#{type})"
    end)
    "Table: #{table}\n#{columns}"
  end)
end
```

**Output format** (injected into agent instructions):
```
Database Schema:

Table: orders
  - id (integer)
  - customer_id (integer)
  - total (numeric)
  - created_at (timestamp without time zone)

Table: customers
  - id (integer)
  - name (character varying)
  - email (character varying)
```

**Alternatives considered**:
- **`pg_catalog` tables**: Rejected — PostgreSQL-specific; `information_schema` is more portable.
- **Parse `\dt` output**: Rejected — requires psql; not programmatic.

## R4: Artifact Display Pattern for SQL Results

**Decision**: The `display` tool emits an artifact signal with `type: "sql_result"` containing `{sql_query, columns, rows, row_count, column_count}`. The ArtifactPlugin broadcasts this to the LiveView, which renders a paginated table. The tool returns `"Query result displayed to user"` to the agent.

**Rationale**: Follows the exact pattern of `DisplayPaper` in `jido_arxiv` — emit artifact, return confirmation text. The artifact data structure mirrors the Python reference implementation's `DataChunk`. Pagination is handled client-side by the LiveView component.

**Implementation sketch**:
```elixir
def run(params, ctx) do
  case QueryExecutor.execute(repo(), params.sql_query) do
    {:ok, result} ->
      artifact_data = %{
        sql_query: params.sql_query,
        columns: result.columns,
        rows: result.rows,
        row_count: result.total_rows,
        column_count: length(result.columns)
      }
      directive = Artifact.emit(ctx, "sql_result", artifact_data)
      {:ok, %{result: "Query result displayed to user"}, directive}
    {:error, msg} ->
      {:error, msg}
  end
end
```

**Alternatives considered**:
- **Direct PubSub broadcast (skip Artifact)**: Rejected — loses agent state integration, versioning, and the established broadcast pattern.
- **Return full data to agent**: Rejected — wastes context window; agent doesn't need the data, only the user does.

## R5: Query Persistence Strategy

**Decision**: Store SQL query text in the `payload` map of existing `ThreadEntry` records. The `kind` field distinguishes tool results. The `payload.sql` field holds the query text for later re-execution. No new database table needed.

**Rationale**: ThreadEntry's `payload` is a flexible JSONB field that already stores tool results. Adding `sql` to the payload is zero-cost — no migration, no new schema. The existing `UITurn` projection passes payload data through to the frontend unchanged, so the LiveView can detect `payload.sql` and render a "re-execute" placeholder.

**Payload structure for SQL tool results**:
```elixir
%{
  role: "tool",
  tool_call_id: "call_abc",
  content: "150 rows returned (showing first 50)...",
  sql: "SELECT * FROM orders WHERE created_at > '2026-01-01'",
  tool_name: "query"  # or "display"
}
```

**Re-execution flow**:
1. LiveView loads conversation → thread entries rendered
2. Entries with `payload.sql` and `tool_name: "display"` show a "Click to load results" placeholder
3. User clicks → LiveView sends `phx-click="reexecute_query"` with the SQL text
4. Server calls `QueryExecutor.execute/2` → results sent back via PubSub or direct assign

**Alternatives considered**:
- **Dedicated `query_results` table**: Rejected — adds migration complexity for no benefit when ThreadEntry payload already supports arbitrary fields.
- **Store results alongside SQL text**: Rejected — user specified: persist SQL only, re-execute on demand.

## R6: Read-Only Database Access

**Decision**: Document how to configure a read-only PostgreSQL connection. Two approaches: (1) create a read-only database user, (2) add `options=-c default_transaction_read_only=on` to the connection URI.

**Rationale**: Both approaches delegate enforcement to the database, which is the correct security boundary. The application code doesn't need to parse or filter SQL — the database rejects write operations. This is production-proven and zero-effort from the code side.

**Documentation content**:
```
# Option 1: Read-only PostgreSQL user
CREATE ROLE sql_agent_reader WITH LOGIN PASSWORD 'secret';
GRANT CONNECT ON DATABASE mydb TO sql_agent_reader;
GRANT USAGE ON SCHEMA public TO sql_agent_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO sql_agent_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO sql_agent_reader;

# Connection URI:
SQL_AGENT_DATABASE_URL=postgres://sql_agent_reader:secret@host/mydb

# Option 2: Force read-only transactions (for an existing user)
SQL_AGENT_DATABASE_URL=postgres://user:pass@host/mydb?options=-c%20default_transaction_read_only%3Don
```

**Alternatives considered**:
- **SQL parsing/filtering in Elixir**: Rejected — fragile, easily bypassed, and unnecessary when the database provides robust access control.
- **Ecto `after_connect` callback**: Possible but less transparent than URI-level config.

## R7: Pagination Strategy

**Decision**: Client-side pagination in the LiveView. The `display` tool sends the full result set as an artifact. The LiveView component renders one page at a time (e.g., 100 rows per page) and lets the user navigate pages.

**Rationale**: For most analytical queries the full result set is manageable in browser memory (a few thousand rows). Server-side pagination would require maintaining cursor state and re-executing with OFFSET/LIMIT, adding complexity. If result sets grow very large, we can add server-side pagination later.

**Alternatives considered**:
- **Server-side OFFSET/LIMIT pagination**: Rejected for v1 — adds complexity and cursor management. Can be added later if needed.
- **Virtual scrolling**: Rejected — requires custom JS; over-engineered for v1.

## R8: Agent Instructions & Schema Injection

**Decision**: Use a custom `request_transformer` module that reads the cached schema text from application state (e.g., `:persistent_term` or a GenServer) and prepends it to the system message before every LLM call.

**Rationale**: Follows the existing `MessageInjector` pattern exactly. Schema is read once at startup and cached. The transformer appends it to every request, ensuring the LLM always has schema context. Using `:persistent_term` is ideal for read-heavy, write-once data like a schema summary.

**Alternatives considered**:
- **Static system_prompt**: Rejected — schema must be dynamic (read from the database at startup).
- **Include schema in first user message only**: Rejected — schema should be in system context for every turn to handle multi-turn conversations.
