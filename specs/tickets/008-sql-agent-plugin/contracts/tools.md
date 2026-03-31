# Tool Contracts: SQL Agent Plugin

**Feature**: 008-sql-agent-plugin
**Date**: 2026-03-31

## Tool: `query`

**Module**: `JidoSql.Tools.Query`
**Purpose**: Execute an exploratory SQL query and return a truncated preview for LLM reasoning.

### Interface

```
Action Name: "sql_query"
Description: "Run a SQL query against the database and return a truncated preview of the results."

Parameters:
  - sql_query: string (required) — The SQL query to execute

Returns on success:
  {:ok, %{result: "formatted text table with truncation note"}}

Returns on error:
  {:error, "Database error description"}
```

### Behavior Contract

1. Executes the provided SQL query against `JidoSql.Repo`
2. Applies a query timeout (default: 15 seconds)
3. On success:
   - Truncates results to max_rows (default: 50) and max_cols (default: 20)
   - Formats as a text table (column headers + row data)
   - Appends truncation indicator if truncated (e.g., "... truncated from 5000 rows to 50")
   - Returns empty indicator "(no rows)" for zero-row results
4. On error:
   - Returns the database error message as plain text
   - LLM can use the error to self-correct and retry
5. SQL query text is stored in the thread entry payload for persistence

### Examples

**Successful query (small result)**:
```
Input:  sql_query: "SELECT name, email FROM users LIMIT 3"
Output: "name       | email\nAlice      | alice@ex.com\nBob        | bob@ex.com\nCharlie    | charlie@ex.com\n\n3 rows returned."
```

**Successful query (truncated)**:
```
Input:  sql_query: "SELECT * FROM orders"
Output: "id | customer_id | total | created_at\n1  | 42          | 99.50 | 2026-01-15\n...\n\nShowing 50 of 12,847 rows (20 of 35 columns). Results truncated."
```

**Error**:
```
Input:  sql_query: "SELECT * FROM nonexistent_table"
Output: {:error, "ERROR 42P01 (undefined_table) relation \"nonexistent_table\" does not exist"}
```

---

## Tool: `display`

**Module**: `JidoSql.Tools.Display`
**Purpose**: Validate a SQL query and create a data panel tab showing the results.

### Interface

```
Action Name: "sql_display"
Description: "Run a SQL query and display the full results to the user as a table in the data panel. Use this when you have the final answer ready."

Parameters:
  - sql_query: string (required) — The SQL query to execute and display

Returns on success:
  {:ok, %{result: "Query result displayed to user (N rows)"}, Directive.Emit artifact}

Returns on error:
  {:error, "Database error description"}
```

### Behavior Contract

1. Executes the provided SQL query against `JidoSql.Repo` to **validate** it works
2. Applies a query timeout (default: 15 seconds)
3. On success:
   - Emits a **deferred artifact** with type `"artifact.sql_results"` using `:merge` mode (append)
   - Artifact data contains only: `%{sql, label, row_count, column_count}` — **no result rows**
   - ArtifactPlugin broadcasts to LiveView via PubSub
   - StoreArtifact appends to the `"sql_results"` list in agent state (→ checkpoint)
   - Returns `"Query result displayed to user (N rows)"` to the agent (not the data)
   - The data panel renderer receives the signal and dynamically executes the SQL to display results
4. On error:
   - Returns the database error message as plain text
   - LLM can use the error to self-correct and retry
   - No artifact is emitted for failed queries

### Artifact Data Structure (deferred — SQL text only)

```elixir
# Single entry appended to the "sql_results" artifact list
%{
  sql: "SELECT * FROM orders WHERE total > 100",
  label: "Orders over $100",
  row_count: 2847,
  column_count: 4
}
```

**Note**: The artifact stores only the query reference. The renderer fetches results dynamically by executing the SQL. This contrasts with the ArXiv agent's materialized artifacts which store full result data.

### Examples

**Successful display**:
```
Input:  sql_query: "SELECT name, COUNT(*) as order_count FROM customers JOIN orders ON customers.id = orders.customer_id GROUP BY name ORDER BY order_count DESC"
Output: "Query result displayed to user (42 rows)"
Side effect: Deferred artifact appended to "sql_results" list; data panel renderer executes SQL and shows table
```

**Error**:
```
Input:  sql_query: "SELECT * FROM orders JION customers ON ..."
Output: {:error, "ERROR 42601 (syntax_error) at or near \"JION\""}
```

---

## Internal Module: `JidoSql.QueryExecutor`

**Purpose**: Shared query execution logic used by both tools.

### Interface

```
execute(repo, sql, opts) :: {:ok, %{columns, rows, total_rows}} | {:error, String.t()}
  opts:
    - timeout: integer (ms, default: 15_000)

truncate(result, max_rows \\ 50, max_cols \\ 20) :: truncated_result
  Returns: %{columns, rows, truncated, total_rows, total_columns}

format_text_table(truncated_result) :: String.t()
  Returns: Human-readable text table for LLM consumption
```

---

## Internal Module: `JidoSql.SchemaIntrospection`

**Purpose**: Read database schema at startup and produce a text summary.

### Interface

```
describe_schema(repo) :: {:ok, String.t()} | {:error, String.t()}
  Returns: Text summary of all tables and columns
  
describe_schema!(repo) :: String.t()
  Returns: Text summary, raises on failure
```

---

## LiveView Contract: Data Panel Renderer

### Real-time display (during conversation)

When the ArtifactPlugin broadcasts an `"artifact.sql_results"` signal, the data panel renderer:
1. Receives the artifact data (`%{sql, label, row_count, column_count}`)
2. Adds a new sub-tab in the `"sql_results"` artifact tab
3. Automatically executes the SQL via `QueryExecutor.execute/2`
4. Renders the paginated result table in the data panel

### Re-execution (past conversations)

When artifacts are restored from checkpoint on revisit:
1. The `"sql_results"` artifact contains a list of `%{sql, label, ...}` entries
2. Renderer shows a sub-tab per entry with a "Click to load results" placeholder
3. User clicks tab → LiveView sends `"reexecute_query"` event with SQL text
4. Server calls `QueryExecutor.execute/2` → paginated results rendered in the tab
5. On error: error message displayed in place of the result table

**Event**: `"reexecute_query"`
**Payload**: `%{"sql" => "SELECT ...", "index" => 0}`
**Response**: Execute query via `QueryExecutor.execute/2`, render results in the corresponding data panel tab
