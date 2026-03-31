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

SQL tool calls and results are stored in the existing `jido_murmur_thread_entries.payload` JSONB field. This drives the **chat column**. No new table or migration required.

**Payload fields added for SQL tools**:

| Field | Type | Description |
|-------|------|-------------|
| sql | String | The SQL query text executed by the tool |
| tool_name | String | `"query"` or `"display"` — distinguishes tool type |

**Example payload for `query` tool result**:
```json
{
  "role": "tool",
  "tool_call_id": "call_abc123",
  "content": "5 rows returned:\n\nid | name | email\n1 | Alice | alice@example.com\n...",
  "sql": "SELECT id, name, email FROM users LIMIT 5",
  "tool_name": "query"
}
```

**Example payload for `display` tool result**:
```json
{
  "role": "tool",
  "tool_call_id": "call_def456",
  "content": "Query result displayed to user (2847 rows)",
  "sql": "SELECT * FROM orders WHERE total > 100",
  "tool_name": "display"
}
```

### Display Artifact (deferred, persisted via StoreArtifact → checkpoint)

Each `display` tool call appends an entry to the `"sql_results"` artifact list in agent state. This drives the **data panel tabs**. Persisted via the existing StoreArtifact → agent state → checkpoint pipeline. No result data is stored — only SQL text.

**Artifact name**: `"sql_results"`
**Merge mode**: `:merge` with `append` — each display call adds to the list

**Entry fields**:

| Field | Type | Description |
|-------|------|-------------|
| sql | String | The SQL query text to display |
| label | String | Human-readable label derived from the query (e.g., "Orders over $100") |
| row_count | integer | Row count from validation execution (for badges) |
| column_count | integer | Column count from validation execution |

**Example artifact data** (stored in `agent.state[:artifacts]["sql_results"]`):
```json
{
  "data": [
    {"sql": "SELECT * FROM orders WHERE total > 100", "label": "Orders over $100", "row_count": 2847, "column_count": 4},
    {"sql": "SELECT name, COUNT(*) FROM customers GROUP BY name", "label": "Customer order counts", "row_count": 156, "column_count": 2}
  ],
  "version": 2,
  "updated_at": "2026-03-31T12:00:00Z",
  "source": "sql_agent"
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
              │        │
              │        └── SQL text ──persisted in──> ThreadEntry.payload (chat column)
              │
              └── display tool ──validates SQL──> emits deferred artifact
                       │
                       ├── %{sql, label} ──persisted in──> StoreArtifact ──> checkpoint (data panel)
                       ├── PubSub broadcast ──> LiveView renderer ──executes SQL──> paginated table
                       └── "displayed" ──returns to──> LLM
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
    │                                      (tool call + result stored in ThreadEntry)
    │
    └── display tool → execute (validate) → emit deferred artifact %{sql, label}
                                             → StoreArtifact appends to "sql_results" list
                                             → PubSub broadcast → renderer executes SQL → table in data panel
                                             → return "displayed" to LLM
                                             (tool call + result stored in ThreadEntry)
```

### Revisit Lifecycle (past conversations)

```
[User opens past conversation]
    │
    ├── Chat column:
    │   ThreadEntry loaded → UITurn.project_entries()
    │   → Messages, tool calls, truncated results rendered in chat
    │
    └── Data panel:
        Artifacts restored from checkpoint
        → agent.state[:artifacts]["sql_results"] = [%{sql, label}, ...]
        → Renderer shows tab per entry with "Click to load" placeholder
        → User clicks tab
           → LiveView executes SQL via QueryExecutor.execute/2
           → Paginated table rendered in data panel tab
           → On error: error message shown in place of table
```
