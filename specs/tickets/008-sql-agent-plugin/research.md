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

**Decision**: The `display` tool validates the SQL query by executing it, then emits a **deferred artifact** with `type: "sql_results"` containing only `%{sql, label}`. The artifact is appended to a list via `:merge` mode. The ArtifactPlugin broadcasts this to the LiveView. The renderer in the data panel dynamically executes the SQL to fetch and display results. The tool returns `"Query result displayed to user"` to the agent.

**Rationale**: The SQL agent exemplifies a **deferred artifact** pattern: the artifact stores only a reference (the SQL query text), and the renderer fetches results dynamically. This avoids persisting large result sets in agent state/checkpoints. It contrasts with the ArXiv agent's **materialized artifact** pattern, where full result data is stored. Both use the same `Artifact.emit` → `StoreArtifact` → checkpoint pipeline — the only difference is what data the artifact contains and how the renderer displays it.

**Implementation sketch**:
```elixir
def run(params, ctx) do
  case QueryExecutor.execute(repo(), params.sql_query) do
    {:ok, result} ->
      artifact_data = %{
        sql: params.sql_query,
        label: derive_label(params.sql_query),
        row_count: result.total_rows,
        column_count: length(result.columns)
      }
      directive = Artifact.emit(ctx, "sql_results", artifact_data,
        mode: :merge, merge: {:append, :data})
      {:ok, %{result: "Query result displayed to user (#{result.total_rows} rows)"}, directive}
    {:error, msg} ->
      {:error, msg}
  end
end
```

**Why validate by executing?**: The tool executes the SQL first to confirm it works before emitting the artifact. This prevents broken queries from becoming permanent data panel tabs. Row/column counts are captured for display metadata (badges, tab labels).

**Alternatives considered**:
- **Store full result rows in artifact**: Rejected — result sets can be huge; storing them in agent state → checkpoint bloats storage and memory. The SQL can always be re-executed.
- **Direct PubSub broadcast (skip Artifact)**: Rejected — loses agent state integration, versioning, checkpoint persistence, and the established display pattern.
- **Return full data to agent**: Rejected — wastes context window; agent doesn't need the data, only the user does.

## R5: Persistence Architecture — Two Layers

**Decision**: Persistence is split into two layers, each serving a distinct UI surface:

1. **Conversation history → ThreadEntry**: Tool calls (including SQL text in `payload.sql`) and tool results (truncated text in `payload.content`) persist in the existing `jido_murmur_thread_entries` table. This drives the **chat column** on revisit. No changes needed — ThreadEntry already stores tool calls and results.

2. **Display tabs → Artifact system**: The `display` tool emits a deferred artifact (`%{sql, label}`) via `Artifact.emit` → `StoreArtifact` → agent state → checkpoint. This drives the **data panel** on revisit. Each display call appends to the `"sql_results"` artifact list.

**Rationale**: The frontend receives state from the backend and displays it. It never parses conversation history to derive data panel content. ThreadEntry drives the chat column. Artifacts drive the data panel. Clean separation.

**Conversation history payload** (unchanged from existing behavior):
```elixir
# Stored automatically by the thread storage adapter
%{
  role: "tool",
  tool_call_id: "call_abc",
  content: "150 rows returned (showing first 50)...",
  # Additional fields in payload for SQL tools:
  sql: "SELECT * FROM orders WHERE created_at > '2026-01-01'",
  tool_name: "query"  # or "display"
}
```

**Artifact data** (persisted via StoreArtifact → checkpoint):
```elixir
# Stored in agent.state[:artifacts]["sql_results"] as a list
[
  %{sql: "SELECT * FROM orders WHERE total > 100", label: "Orders over $100"},
  %{sql: "SELECT name, COUNT(*) FROM customers GROUP BY name", label: "Customer order counts"}
]
```

**On revisit — chat column**:
1. ThreadEntry loaded → `UITurn.project_entries()` → chat messages rendered
2. Tool call entries show SQL text and truncated results inline (conversation context)

**On revisit — data panel**:
1. Artifacts restored from checkpoint → `"sql_results"` list available
2. Renderer shows a tab per entry with "Click to load" placeholder
3. User clicks tab → LiveView executes SQL → paginated table rendered

**Alternatives considered**:
- **ThreadEntry-only (parse chat for display tabs)**: Rejected — puts too much responsibility on the frontend; requires parsing conversation history to derive data panel content.
- **Artifact-only (skip ThreadEntry)**: Rejected — conversation history already persists tool calls via ThreadEntry; no reason to change that.
- **Dedicated `query_results` table**: Rejected — adds migration complexity; both existing systems (ThreadEntry + artifacts) already handle their respective concerns.

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

**Decision**: Server-side pagination in the data panel renderer. When a display tab is viewed (or clicked on revisit), the LiveView executes the SQL query and paginates results server-side (e.g., 100 rows per page). The renderer sends one page of data at a time and lets the user navigate pages.

**Rationale**: Since the display tool uses a deferred artifact pattern (SQL text only, no stored results), the renderer must execute the SQL to fetch data. Pagination happens at fetch time — the renderer can use `LIMIT/OFFSET` wrapping or Elixir-side slicing. This avoids sending large result sets to the browser.

**Alternatives considered**:
- **Client-side pagination (send all rows)**: Rejected — since results are fetched dynamically, there's no reason to transfer all rows to the browser at once.
- **Virtual scrolling**: Rejected — requires custom JS; over-engineered for v1.

## R8: Agent Instructions & Schema Injection

**Decision**: Use a custom `request_transformer` module that reads the cached schema text from application state (e.g., `:persistent_term` or a GenServer) and prepends it to the system message before every LLM call.

**Rationale**: Follows the existing `MessageInjector` pattern exactly. Schema is read once at startup and cached. The transformer appends it to every request, ensuring the LLM always has schema context. Using `:persistent_term` is ideal for read-heavy, write-once data like a schema summary.

**Alternatives considered**:
- **Static system_prompt**: Rejected — schema must be dynamic (read from the database at startup).
- **Include schema in first user message only**: Rejected — schema should be in system context for every turn to handle multi-turn conversations.
