# Quickstart: SQL Agent Plugin

**Feature**: 008-sql-agent-plugin
**Date**: 2026-03-31

## Prerequisites

- Elixir ≥ 1.15, Erlang/OTP
- PostgreSQL (for both the application database and the target SQL database)
- The Murmur application running (`mix setup && mix phx.server`)

## Setup

### 1. Configure the target database

Set the `SQL_AGENT_DATABASE_URL` environment variable to point at the database you want the SQL agent to query:

```bash
export SQL_AGENT_DATABASE_URL="postgres://user:password@localhost:5432/my_target_database"
```

### 2. Start the application

```bash
mix setup
mix phx.server
```

The SQL agent will:
1. Connect to the target database on startup
2. Read the schema (tables + columns)
3. Register itself in the agent catalog

### 3. Use the SQL agent

1. Open the chat interface in the browser
2. Select the **SQL Agent** from the agent picker
3. Ask a question like "Show me all tables" or "How many orders were placed last month?"

## Read-Only Configuration (PostgreSQL)

To prevent the SQL agent from modifying data, configure a read-only database connection:

### Option A: Create a read-only database user (recommended)

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

With either option, any write query (INSERT, UPDATE, DELETE, DROP) will be rejected by the database, and the agent will inform the user.

## Configuration Options

All configuration is in `config/config.exs` and environment-specific files:

| Setting | Default | Description |
|---------|---------|-------------|
| `SQL_AGENT_DATABASE_URL` | (required) | Connection URI for the target database |
| Query timeout | 15,000 ms | Maximum execution time per query |
| Truncation rows | 50 | Max rows returned to the agent via `query` tool |
| Truncation columns | 20 | Max columns returned to the agent via `query` tool |
| Connection pool size | 5 | Number of database connections in the pool |

## Verifying It Works

1. Start the app and check logs for:
   ```
   [info] JidoSql: Connected to target database. Schema loaded: 12 tables, 87 columns.
   ```

2. Ask the SQL agent: **"What tables are in the database?"**
   - It should list all tables without consulting the database (from its instructions)

3. Ask: **"Show me the first 5 rows from [any_table]"**
   - It should use the `query` tool to explore, then `display` to show results

4. Restart the server, reopen the conversation:
   - Chat history should be visible
   - Display results should show "Click to load" placeholders
   - Clicking should re-execute and show current data
