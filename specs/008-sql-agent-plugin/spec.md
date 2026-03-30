# Feature Specification: SQL Agent Plugin

**Feature Branch**: `008-sql-agent-plugin`  
**Created**: 2026-03-30  
**Status**: Draft  
**Input**: User description: "Add a new agent powered by a SQL plugin that lets users ask natural-language questions about any SQL database, with query and display tools."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ask a Question About the Database (Priority: P1)

A user selects the SQL agent in the chat interface and asks a natural-language question such as "How many orders were placed last month?" The agent interprets the question, generates one or more SQL queries using the `query` tool to explore and analyze the data, and then uses the `display` tool to present the final answer as a table the user can see.

**Why this priority**: This is the core value proposition — without the ability to ask questions and see results, no other functionality matters.

**Independent Test**: Can be fully tested by sending a chat message to the SQL agent and verifying that the agent returns a visible table of query results to the user.

**Acceptance Scenarios**:

1. **Given** the SQL agent is running and connected to a database, **When** a user asks "Show me all tables in the database", **Then** the agent uses the `query` tool to discover tables and uses the `display` tool to show the results.
2. **Given** the SQL agent is running, **When** a user asks "How many rows are in the users table?", **Then** the agent generates and executes the appropriate SQL query and displays the count to the user.
3. **Given** the SQL agent receives a question, **When** the generated SQL query contains an error, **Then** the database error is surfaced back to the agent so it can self-correct and retry with a valid query.

---

### User Story 2 - Agent Knows the Database Schema (Priority: P1)

When the SQL agent starts, it automatically reads the database schema (table names and column names/types) and includes a summary in its system instructions. This enables the agent to generate accurate queries without guessing table or column names.

**Why this priority**: Without schema awareness the agent would hallucinate table/column names, making it practically useless. This is a prerequisite for Story 1.

**Independent Test**: Can be tested by starting the agent and verifying its instructions contain an accurate description of the connected database schema.

**Acceptance Scenarios**:

1. **Given** a database with tables and columns, **When** the SQL agent is started, **Then** the agent's instructions include a summary listing every table name and its columns.
2. **Given** the database schema changes and the agent is restarted, **When** the agent starts up, **Then** the schema summary reflects the current state of the database.

---

### User Story 3 - Query Results Are Truncated for the Agent (Priority: P2)

When the agent uses the `query` tool to explore data, the returned results are truncated (both in columns and rows) so that very large result sets do not overwhelm the agent's context window. The agent sees enough data to reason about the answer but not so much that it causes failures.

**Why this priority**: Without truncation, a single exploratory query on a large table could exceed the context window and break the conversation. This is essential for reliability.

**Independent Test**: Can be tested by executing a query that returns thousands of rows and verifying the tool result is capped to a readable preview.

**Acceptance Scenarios**:

1. **Given** a query returns more rows than a configured maximum, **When** the `query` tool executes it, **Then** the result returned to the agent is truncated to the maximum row count with an indication that results were truncated.
2. **Given** a query returns more columns than a configured maximum, **When** the `query` tool executes it, **Then** the result returned to the agent has excess columns removed.
3. **Given** a query returns a small result set, **When** the `query` tool executes it, **Then** the full result is returned without truncation.

---

### User Story 4 - User Sees Full Display Results (Priority: P2)

When the agent decides the final answer is ready, it uses the `display` tool which sends the complete, untruncated query results to the user's UI. The user sees a structured table view. The agent only receives a confirmation message ("result sent to user") to keep its context window lean.

**Why this priority**: The display tool is what makes the user experience great — seeing full tabular data rather than a text summary. Depends on P1 stories.

**Independent Test**: Can be tested by having the agent call the `display` tool and verifying the user's UI receives the full result set while the agent receives only a confirmation.

**Acceptance Scenarios**:

1. **Given** the agent calls the `display` tool with a valid SQL query, **When** the query executes successfully, **Then** the user's interface shows a paginated table with columns and rows from the result.
2. **Given** the agent calls the `display` tool, **When** the query executes successfully, **Then** the agent receives only the message "Query result displayed to user" (not the full data).
3. **Given** the agent calls the `display` tool with an invalid query, **When** the database returns an error, **Then** the error is surfaced back to the agent so it can correct itself.
4. **Given** a displayed query returns many rows, **When** the user views the result, **Then** results are paginated and the user can navigate between pages.

---

### User Story 5 - Read-Only Database Access (Priority: P3)

The system provides clear documentation on how to configure the database connection as read-only, so that the SQL agent cannot accidentally modify data. For PostgreSQL this is achievable through the connection URI by connecting with a read-only database user or setting `default_transaction_read_only=on`.

**Why this priority**: Important for production safety, but does not block core functionality. Users who want write protection can follow the docs.

**Independent Test**: Can be tested by following the documented instructions to create a read-only connection and verifying that write queries (INSERT, UPDATE, DELETE) are rejected by the database.

**Acceptance Scenarios**:

1. **Given** the documentation describes how to configure a read-only connection for PostgreSQL, **When** an operator follows the instructions and connects the SQL agent to the database, **Then** any write query (INSERT, UPDATE, DELETE, DROP) is rejected by the database.
2. **Given** the agent is connected via a read-only connection, **When** the agent attempts a write query, **Then** the database returns an error which the agent surfaces to the user as a clear explanation.

---

### Edge Cases

- What happens when the database is unreachable at agent startup? The schema discovery should fail gracefully with a clear error, and the agent should not start without schema context.
- What happens when a query takes too long? The system should enforce a query timeout so a single expensive query does not hang the agent indefinitely.
- What happens when the query result set is empty? The `query` tool should return a clear "(no rows)" indicator; the `display` tool should show an empty table with column headers.
- What happens when the database connection is lost mid-conversation? The tool should return a connection error to the agent so it can inform the user.
- What happens when a user asks a question that cannot be answered from the database? The agent should explain that the data does not support the question based on the schema it has.

### User Story 6 - Persistent Conversation and Query History (Priority: P2)

When a user returns to a past conversation with the SQL agent — even after a server restart — they can see their full chat history including all SQL queries the agent executed. Displayed query results are re-executed on demand from the stored SQL text, so the user always sees current data without the system needing to persist large result sets.

**Why this priority**: Persistence is essential for a production-quality experience. Users expect to pick up where they left off. Storing only SQL text keeps this extremely lightweight.

**Independent Test**: Can be tested by having a conversation with the SQL agent, restarting the server, reopening the conversation, and verifying the chat history and re-executed query results are visible.

**Acceptance Scenarios**:

1. **Given** a user had a previous conversation with the SQL agent, **When** the server restarts and the user opens that conversation, **Then** the full chat history (messages and queries) is visible.
2. **Given** a past conversation contains displayed query results, **When** the user views the conversation, **Then** each query result shows a placeholder that the user can click to re-execute the stored SQL and view current results.
3. **Given** a stored SQL query references a table that has since been dropped, **When** the query is re-executed, **Then** the system shows a clear error message instead of the result.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a SQL agent profile that can be registered in the agent catalog and selected by users in the chat interface.
- **FR-002**: System MUST dynamically read the connected database schema (table names, column names, and column types) at agent startup and include it in the agent's system instructions.
- **FR-003**: System MUST provide a `query` tool that executes any SQL query against the connected database and returns the result to the agent.
- **FR-004**: The `query` tool MUST truncate results that exceed configurable row and column limits, including an indicator that truncation occurred.
- **FR-005**: The `query` tool MUST surface database errors (syntax errors, permission errors, timeout errors) back to the agent as plain text so the agent can self-correct.
- **FR-006**: System MUST provide a `display` tool that executes a SQL query and sends the results to the user's interface with pagination support.
- **FR-007**: The `display` tool MUST return only a confirmation message ("Query result displayed to user") to the agent, not the full data.
- **FR-008**: The `display` tool MUST surface database errors back to the agent for self-correction.
- **FR-009**: System MUST enforce a query execution timeout to prevent long-running queries from blocking the agent.
- **FR-010**: System MUST be compatible with any SQL database that supports standard SQL queries through its database connection adapter.
- **FR-011**: System MUST provide documentation explaining how to configure a read-only database connection, with specific instructions for PostgreSQL (e.g., using a read-only user or `default_transaction_read_only=on` connection parameter).
- **FR-015**: System MUST use a separate database connection, configured via its own URI, independent from the application's main database. The SQL agent MUST NOT have access to internal application tables.

- **FR-012**: System MUST persist all SQL queries executed by the agent (both `query` and `display` tool calls) as part of the conversation thread, storing only the SQL text — not the result data.
- **FR-013**: System MUST support re-executing stored SQL queries on demand (lazy) when a user interacts with a past query result placeholder, so results reflect current database state without executing all queries on page load.
- **FR-014**: System MUST gracefully handle re-execution failures (e.g., dropped tables, changed schema) by showing a clear error in place of the result.

### Key Entities

- **SQL Agent Profile**: The agent configuration that defines the SQL agent's name, description, tools (`query`, `display`), and plugins. Registered in the agent catalog.
- **Database Connection**: The runtime connection to the target SQL database, configured via a connection URI. Used by tools to execute queries and by the startup process to read schema.
- **Database Schema Summary**: A text description of all tables and their columns (name, type) in the connected database. Generated at startup and injected into the agent's system instructions.
- **Query Result**: The output of a SQL query, consisting of column names and row data. May be truncated (for the `query` tool) or full (for the `display` tool).
- **Stored Query**: The SQL text of a query executed by the agent, persisted as part of the conversation thread. Does not include result data — results are re-derived by re-executing the SQL on demand.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can ask a natural-language question about a connected database and receive a tabular answer within a single conversation turn (excluding complex multi-step analysis).
- **SC-002**: The agent correctly generates valid SQL for at least 80% of common analytical questions (counts, aggregations, filters, joins) without requiring self-correction.
- **SC-003**: Query results returned to the agent via the `query` tool never exceed the configured truncation limits, regardless of the actual result size.
- **SC-004**: Full query results displayed to the user via the `display` tool are paginated and navigable, with no data loss across pages.
- **SC-005**: When the agent generates an invalid query, it self-corrects and retries successfully within 3 attempts for at least 90% of common SQL errors (syntax, missing table, wrong column name).
- **SC-006**: A operator following the read-only documentation can configure a PostgreSQL connection that rejects all write operations within 5 minutes.

## Clarifications

### Session 2026-03-30

- Q: Which query results should be persisted (display only, all results, or queries+failures)? → A: Persist only the SQL query text (not result data) for all tool calls; re-execute queries on demand to retrieve current results.
- Q: Should the SQL agent connect to the same database as the application or a separate one? → A: Separate database connection configured via its own URI, independent from the application's Murmur.Repo.
- Q: How should past query results be presented when a user revisits a conversation? → A: Lazy — show a placeholder per query result; re-execute only when the user clicks or scrolls to it.
- Q: What is the maximum result size the display tool should send to the user? → A: Paginate results rather than imposing a hard cap. The UI fetches and displays results one page at a time.
- Q: Should stored queries have a retention policy? → A: No retention policy — keep forever. Query text is tiny; cleanup can be added later if needed.

## Assumptions

- The SQL plugin targets standard SQL databases; initial implementation will use a separate, dedicated database connection (not the application's Murmur.Repo) configured via its own connection URI. This isolates agent queries from application data.
- Schema discovery at startup is sufficient; mid-session schema changes are not supported (agent restart required).
- The agent is responsible for generating SQL; the tools are "dumb" executors that do not validate or transform the SQL beyond execution.
- Query timeout defaults will follow standard database connection defaults (e.g., 15 seconds) and can be configured.
- Truncation limits for the `query` tool will use sensible defaults (e.g., 50 rows, 20 columns) that can be overridden via configuration.
- The `display` tool's delivery mechanism to the user's UI will follow the existing project pattern for sending structured data to the frontend (similar to how `DisplayPaper` in the arXiv agent works). Results are paginated on the client side to handle large result sets without browser performance issues.
- No retention policy for stored query text; conversations and queries are kept indefinitely. Storage impact is negligible since only SQL text is persisted.
- Read-only documentation focuses on PostgreSQL; for other databases, users are expected to configure access control through their own database administration tools.
- The SQL agent persists conversation history and SQL query text via the existing thread entry storage (ThreadEntry). Only the SQL text is stored — result data is re-executed on demand from the database. This keeps storage lightweight even with many queries.
