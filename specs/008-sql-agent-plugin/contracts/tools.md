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
**Purpose**: Execute a SQL query and send the full, paginated results to the user's UI.

### Interface

```
Action Name: "sql_display"
Description: "Run a SQL query and display the full results to the user as a table. Use this when you have the final answer ready."

Parameters:
  - sql_query: string (required) — The SQL query to execute and display

Returns on success:
  {:ok, %{result: "Query result displayed to user"}, Directive.Emit artifact}

Returns on error:
  {:error, "Database error description"}
```

### Behavior Contract

1. Executes the provided SQL query against `JidoSql.Repo`
2. Applies a query timeout (default: 15 seconds)
3. On success:
   - Emits an artifact signal with type `"artifact.sql_result"`
   - Artifact data contains: `{sql_query, columns, rows, row_count, column_count}`
   - ArtifactPlugin broadcasts to LiveView via PubSub
   - Returns `"Query result displayed to user"` to the agent (not the data)
4. On error:
   - Returns the database error message as plain text
   - LLM can use the error to self-correct and retry
5. SQL query text is stored in the thread entry payload for persistence

### Artifact Signal Data Structure

```elixir
%{
  sql_query: "SELECT * FROM orders WHERE total > 100",
  columns: ["id", "customer_id", "total", "created_at"],
  rows: [[1, 42, 150.00, "2026-01-15"], ...],
  row_count: 2847,
  column_count: 4
}
```

### Examples

**Successful display**:
```
Input:  sql_query: "SELECT name, COUNT(*) as order_count FROM customers JOIN orders ON customers.id = orders.customer_id GROUP BY name ORDER BY order_count DESC"
Output: "Query result displayed to user"
Side effect: Artifact broadcast to LiveView with full result set
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

## LiveView Contract: Re-execution

**Event**: `"reexecute_query"`
**Payload**: `%{"sql" => "SELECT ...", "entry_id" => "..."}`
**Response**: Execute query via `QueryExecutor.execute/2`, send results as assign or PubSub update

This event is triggered when a user clicks a "Load results" placeholder on a past conversation's display tool result. The LiveView executes the stored SQL and renders the paginated table.
