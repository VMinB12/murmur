# JidoSql — SQL Agent Plugin

SQL agent plugin that lets users ask natural-language questions about any SQL database. The agent connects to a separate, independently configured database, reads its schema at startup, and provides two tools: `query` (exploratory, truncated results for the LLM) and `display` (full paginated results for the user).

## Setup

### 1. Configure the target database

Set the `SQL_AGENT_DATABASE_URL` environment variable:

```bash
export SQL_AGENT_DATABASE_URL="postgres://user:password@localhost:5432/my_target_database"
```

### 2. Start the application

```bash
mix setup
mix phx.server
```

The SQL agent will connect, read the schema, and register itself in the agent catalog.

### 3. Verify

Check the logs for:

```
[info] JidoSql: Connected to target database. Schema loaded: 12 tables, 87 columns.
```

## Configuration

| Setting | Config key | Default | Description |
|---------|-----------|---------|-------------|
| Database URL | `SQL_AGENT_DATABASE_URL` env var | (required) | Connection URI for the target database |
| Max rows | `:jido_sql, :max_rows` | 50 | Max rows returned to the agent via `query` tool |
| Max columns | `:jido_sql, :max_columns` | 20 | Max columns returned to the agent via `query` tool |
| Pool size | `SQL_AGENT_POOL_SIZE` env var | 5 | Number of database connections |

## Read-Only Configuration (Recommended for Production)

To prevent the SQL agent from modifying data, configure a read-only database connection. Two approaches:

### Option A: Create a read-only PostgreSQL user (recommended)

```sql
-- Run as a PostgreSQL superuser
CREATE ROLE sql_agent_reader WITH LOGIN PASSWORD 'your_secure_password';
GRANT CONNECT ON DATABASE your_database TO sql_agent_reader;
GRANT USAGE ON SCHEMA public TO sql_agent_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO sql_agent_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO sql_agent_reader;
```

Then set the connection URI:

```bash
export SQL_AGENT_DATABASE_URL="postgres://sql_agent_reader:your_secure_password@localhost:5432/your_database"
```

### Option B: Force read-only transactions

Add `options=-c default_transaction_read_only=on` to the connection URI:

```bash
export SQL_AGENT_DATABASE_URL="postgres://user:password@localhost:5432/your_database?options=-c%20default_transaction_read_only%3Don"
```

With either option, any write query (INSERT, UPDATE, DELETE, DROP) is rejected by the database. The agent will surface the error and inform the user.

## Architecture

```
JidoSql.Repo ── external target database
  ├── SchemaIntrospection → :persistent_term cache → agent instructions
  └── QueryExecutor → raw SQL execution
       ├── Tools.Query → truncated text for LLM reasoning
       └── Tools.Display → deferred artifact → data panel tab
```

When used with `jido_murmur`, SQL-agent requests enter through `JidoMurmur.Ingress`. Busy-run follow-up delivery is handled natively by `jido_ai`, while `JidoSql.RequestTransformer` only enriches the system prompt with cached schema context.

## Dependencies

**Requires:** `jido ~> 2.2`, `jido_ai ~> 2.1`, `jido_action ~> 2.2`, `jido_artifacts` (umbrella), `jido_murmur` (umbrella), `ecto_sql ~> 3.0`, `postgrex`, `jason ~> 1.0`
