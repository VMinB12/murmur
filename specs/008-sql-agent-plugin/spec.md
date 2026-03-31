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

When the agent decides the final answer is ready, it uses the `display` tool which creates a new tab in the data panel showing the query results as a paginated table. The agent only receives a confirmation message ("result sent to user") to keep its context window lean. Each `display` call adds a tab to the data panel. The artifact stores only the SQL text — results are fetched dynamically by the renderer when the tab is viewed.

**Why this priority**: The display tool is what makes the user experience great — seeing full tabular data rather than a text summary. Depends on P1 stories.

**Independent Test**: Can be tested by having the agent call the `display` tool and verifying a new tab appears in the data panel with the query results while the agent receives only a confirmation.

**Acceptance Scenarios**:

1. **Given** the agent calls the `display` tool with a valid SQL query, **When** the query executes successfully, **Then** a new tab appears in the data panel showing a paginated table with columns and rows.
2. **Given** the agent calls the `display` tool, **When** the query executes successfully, **Then** the agent receives only the message "Query result displayed to user" (not the full data).
3. **Given** the agent calls the `display` tool with an invalid query, **When** the database returns an error, **Then** the error is surfaced back to the agent so it can correct itself.
4. **Given** a displayed query returns many rows, **When** the user views the tab, **Then** results are paginated and the user can navigate between pages.
5. **Given** the agent calls the `display` tool multiple times, **When** the user views the data panel, **Then** each display call has its own tab.

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

When a user returns to a past conversation with the SQL agent — even after a server restart — they see two things restored: (1) the full chat history in the conversation column (messages, tool calls, truncated results), and (2) the display tabs in the data panel. Conversation history is persisted via the existing thread entry storage (ThreadEntry). Display tabs are persisted via the artifact system (StoreArtifact → checkpoint), which stores only the SQL text per displayed query. When the user clicks a restored display tab, the SQL is re-executed to show current results.

**Why this priority**: Persistence is essential for a production-quality experience. Users expect to pick up where they left off. Storing only SQL text in the artifact keeps this extremely lightweight.

**Independent Test**: Can be tested by having a conversation with the SQL agent, restarting the server, reopening the conversation, and verifying the chat history is visible and the data panel tabs reappear with re-executable queries.

**Acceptance Scenarios**:

1. **Given** a user had a previous conversation with the SQL agent, **When** the server restarts and the user opens that conversation, **Then** the full chat history (messages, tool calls, truncated results) is visible in the conversation column.
2. **Given** a past conversation contains display tool calls, **When** the user views the conversation, **Then** the data panel shows tabs for each displayed query, each with a "Click to load" placeholder.
3. **Given** a user clicks a restored display tab, **When** the SQL executes successfully, **Then** the tab shows current results from the database.
4. **Given** a stored SQL query references a table that has since been dropped, **When** the query is re-executed, **Then** the system shows a clear error message in the tab instead of the result.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a SQL agent profile that can be registered in the agent catalog and selected by users in the chat interface.
- **FR-002**: System MUST dynamically read the connected database schema (table names, column names, and column types) at agent startup and include it in the agent's system instructions.
- **FR-003**: System MUST provide a `query` tool that executes any SQL query against the connected database and returns the result to the agent.
- **FR-004**: The `query` tool MUST truncate results that exceed configurable row and column limits, including an indicator that truncation occurred.
- **FR-005**: The `query` tool MUST surface database errors (syntax errors, permission errors, timeout errors) back to the agent as plain text so the agent can self-correct.
- **FR-006**: System MUST provide a `display` tool that executes a SQL query, validates it succeeds, and emits an artifact containing only the SQL text to create a new tab in the user's data panel. The renderer fetches results dynamically.
- **FR-007**: The `display` tool MUST return only a confirmation message ("Query result displayed to user") to the agent, not the full data.
- **FR-008**: The `display` tool MUST surface database errors back to the agent for self-correction.
- **FR-009**: System MUST enforce a query execution timeout to prevent long-running queries from blocking the agent.
- **FR-010**: System MUST be compatible with any SQL database that supports standard SQL queries through its database connection adapter.
- **FR-011**: System MUST provide documentation explaining how to configure a read-only database connection, with specific instructions for PostgreSQL (e.g., using a read-only user or `default_transaction_read_only=on` connection parameter).
- **FR-015**: System MUST use a separate database connection, configured via its own URI, independent from the application's main database. The SQL agent MUST NOT have access to internal application tables.

- **FR-012**: Conversation history (tool calls and truncated results) MUST persist via the existing ThreadEntry storage. This drives the chat column on revisit.
- **FR-013**: Display queries MUST persist via the artifact system (StoreArtifact → checkpoint). Only the SQL text is stored per displayed query. This drives the data panel tabs on revisit.
- **FR-014**: The data panel renderer MUST support re-executing stored SQL queries on demand (lazy) when a user clicks a display tab, so results reflect current database state without executing all queries on page load.
- **FR-016**: System MUST gracefully handle re-execution failures (e.g., dropped tables, changed schema) by showing a clear error in the data panel tab in place of the result.

### Key Entities

- **SQL Agent Profile**: The agent configuration that defines the SQL agent's name, description, tools (`query`, `display`), and plugins. Registered in the agent catalog.
- **Database Connection**: The runtime connection to the target SQL database, configured via a connection URI. Used by tools to execute queries and by the startup process to read schema.
- **Database Schema Summary**: A text description of all tables and their columns (name, type) in the connected database. Generated at startup and injected into the agent's system instructions.
- **Query Result**: The output of a SQL query, consisting of column names and row data. May be truncated (for the `query` tool) or dynamically fetched (for the `display` tool renderer).
- **Display Artifact**: The SQL text of a displayed query, persisted via the artifact system (StoreArtifact → agent state → checkpoint). Each `display` call appends an entry to the `"sql_results"` artifact list. Results are re-derived by re-executing the SQL on demand in the data panel renderer.

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

- Q: Which query results should be persisted (display only, all results, or queries+failures)? → A: Conversation history (including tool calls with SQL text and truncated results) persists via ThreadEntry. Display query SQL text persists via the artifact system. Result data is never stored — re-executed on demand.
- Q: Should the SQL agent connect to the same database as the application or a separate one? → A: Separate database connection configured via its own URI, independent from the application's Murmur.Repo.
- Q: How should past query results be presented when a user revisits a conversation? → A: Two layers: (1) chat column shows conversation history from ThreadEntry, (2) data panel shows display tabs from artifacts (StoreArtifact → checkpoint) with lazy re-execution on click.
- Q: What is the maximum result size the display tool should send to the user? → A: Paginate results rather than imposing a hard cap. The renderer fetches and displays results one page at a time.
- Q: Should stored queries have a retention policy? → A: No retention policy — keep forever. Query text is tiny; cleanup can be added later if needed.
- Q: Where does display tab data live? → A: In the artifact system. The `display` tool emits to the `"sql_results"` artifact using `:merge` mode (append). Artifact data contains only `%{sql, label}` — no result rows. The renderer executes SQL dynamically.

## Assumptions

- The SQL plugin targets standard SQL databases; initial implementation will use a separate, dedicated database connection (not the application's Murmur.Repo) configured via its own connection URI. This isolates agent queries from application data.
- Schema discovery at startup is sufficient; mid-session schema changes are not supported (agent restart required).
- The agent is responsible for generating SQL; the tools are "dumb" executors that do not validate or transform the SQL beyond execution.
- Query timeout defaults will follow standard database connection defaults (e.g., 15 seconds) and can be configured.
- Truncation limits for the `query` tool will use sensible defaults (e.g., 50 rows, 20 columns) that can be overridden via configuration.
- The `display` tool uses the artifact system (`Artifact.emit` → `StoreArtifact` → checkpoint) to persist SQL text and create data panel tabs. This follows the same pattern as `DisplayPaper` in the arXiv agent, but uses a "deferred" artifact pattern: the artifact stores only the query reference (SQL text), and the renderer fetches results dynamically. This avoids persisting large result sets.
- No retention policy for stored query text; conversations and queries are kept indefinitely. Storage impact is negligible since only SQL text is persisted.
- Read-only documentation focuses on PostgreSQL; for other databases, users are expected to configure access control through their own database administration tools.
- Conversation history persists via ThreadEntry (chat column). Display artifacts persist via StorerArtifact → checkpoint (data panel). These are two separate persistence layers with distinct purposes.
