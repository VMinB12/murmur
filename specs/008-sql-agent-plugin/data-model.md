# Data Model: SQL Agent Plugin

**Feature**: 008-sql-agent-plugin
**Date**: 2026-03-31

## Entities

### JidoSql.Repo

Ecto Repo for the external target database. Not managed by the application — no migrations, no schemas. Used solely for raw SQL execution and schema introspection.

**Configuration**:
- `otp_app: :jido_sql`
- `adapter: Ecto.Adapters.Postgres`
- Connection URI via `SQL_AGENT_DATABASE_URL`
- Pool size: 5 (configurable)
- Default query timeout: 15,000 ms

### Schema Summary (runtime, in-memory)

A text string generated at startup by reading `information_schema.columns`. Stored in `:persistent_term` for zero-cost reads by the request transformer.

**Fields** (conceptual — not an Ecto schema):

| Field | Type | Description |
|-------|------|-------------|
| text | String | Human-readable schema description for LLM instructions |
| tables | list(Table) | Structured representation for programmatic use |

**Table sub-structure**:

| Field | Type | Description |
|-------|------|-------------|
| name | String | Table name (e.g., `"orders"`) |
| columns | list(Column) | Ordered list of columns |

**Column sub-structure**:

| Field | Type | Description |
|-------|------|-------------|
| name | String | Column name (e.g., `"customer_id"`) |
| type | String | Data type (e.g., `"integer"`, `"character varying"`) |

### Query Result (runtime, ephemeral)

Returned by `QueryExecutor.execute/2`. Not persisted — only the SQL text is persisted via ThreadEntry.

| Field | Type | Description |
|-------|------|-------------|
| columns | list(String) | Column names from the result set |
| rows | list(list(term)) | Row data as nested lists |
| total_rows | integer | Total row count before truncation |

### Truncated Result (runtime, derived)

Returned by `QueryExecutor.truncate/3`. Sent to the LLM via the `query` tool.

| Field | Type | Description |
|-------|------|-------------|
| columns | list(String) | Column names (may be subset) |
| rows | list(list(term)) | Row data (may be subset) |
| truncated | boolean | Whether truncation was applied |
| total_rows | integer | Original row count |
| total_columns | integer | Original column count |

### ThreadEntry Payload Extension (existing schema, no migration)

SQL tool results are stored in the existing `jido_murmur_thread_entries.payload` JSONB field. No new table or migration required.

**Payload fields added for SQL tools**:

| Field | Type | Description |
|-------|------|-------------|
| sql | String | The SQL query text executed by the tool |
| tool_name | String | `"query"` or `"display"` — distinguishes tool type |
| row_count | integer | Number of rows in the result (for display metadata) |
| truncated | boolean | Whether the result was truncated (for `query` tool) |

**Example payload for `query` tool result**:
```json
{
  "role": "tool",
  "tool_call_id": "call_abc123",
  "content": "5 rows returned:\n\nid | name | email\n1 | Alice | alice@example.com\n...",
  "sql": "SELECT id, name, email FROM users LIMIT 5",
  "tool_name": "query",
  "row_count": 5,
  "truncated": false
}
```

**Example payload for `display` tool result**:
```json
{
  "role": "tool",
  "tool_call_id": "call_def456",
  "content": "Query result displayed to user",
  "sql": "SELECT * FROM orders WHERE total > 100",
  "tool_name": "display",
  "row_count": 2847
}
```

## Relationships

```
JidoSql.Repo ──executes──> Target Database (external)
     │
     ├── SchemaIntrospection ──reads──> information_schema.columns
     │        │
     │        └── produces ──> Schema Summary (stored in :persistent_term)
     │                              │
     │                              └── injected into ──> Agent Instructions
     │
     └── QueryExecutor ──executes──> Raw SQL
              │
              ├── query tool ──truncates──> Truncated Result ──returns to──> LLM
              │
              └── display tool ──emits──> Artifact Signal ──broadcasts to──> LiveView
                       │
                       └── SQL text ──persisted in──> ThreadEntry.payload
```

## State Transitions

### Schema Summary Lifecycle

```
[App Start] → SchemaIntrospection.describe_schema(repo)
    │
    ├── {:ok, text} → :persistent_term.put({JidoSql, :schema}, text)
    │                  Agent ready to accept queries
    │
    └── {:error, reason} → Log error, agent not registered
                           (fail-fast: no schema = no agent)
```

### Query Execution Lifecycle

```
[User Message] → Agent generates SQL
    │
    ├── query tool → execute → truncate → return text to LLM
    │                                      (SQL stored in thread payload)
    │
    └── display tool → execute → emit artifact → broadcast to LiveView
                                                  return "displayed" to LLM
                                                  (SQL stored in thread payload)
```

### Re-execution Lifecycle (past conversations)

```
[User opens past conversation] → Thread entries loaded
    │
    ├── Entries with payload.tool_name == "display"
    │   → Render placeholder: "Click to load results"
    │
    └── User clicks placeholder
        → LiveView sends "reexecute_query" event with SQL text
        → QueryExecutor.execute(repo, sql)
        → Results sent to client for paginated display
```
