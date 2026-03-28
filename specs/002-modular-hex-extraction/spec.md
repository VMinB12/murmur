# Feature Specification: Modular Hex Package Extraction

**Feature Branch**: `002-modular-hex-extraction`  
**Created**: 2026-03-28  
**Status**: Draft  
**Input**: Extract Murmur's multi-agent architecture into reusable Hex packages organized as a Mix umbrella project, with `jido_murmur` (backend orchestration), `jido_murmur_web` (optional LiveView components), `jido_tasks` (task management tools), and `jido_arxiv` (academic research tools) as independently publishable packages. The current Murmur application remains as a demo/reference app. Packages must be Jido-native — they provide pre-built Jido components (actions, plugins, storage adapters, LiveView helpers) without abstracting away or wrapping Jido's own APIs.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Consumer Bootstraps a Multi-Agent App Using jido_murmur (Priority: P1)

A developer building a new multi-agent application adds `jido_murmur` as a dependency, runs the install generator, configures their Repo/PubSub/Jido modules, defines agent profiles using standard Jido macros, and has a working multi-agent workspace with message orchestration, streaming, and persistence — without needing to write orchestration logic from scratch.

**Why this priority**: This is the core value proposition. If a consumer cannot install the package and get a working multi-agent backend with minimal boilerplate, none of the other packages matter.

**Independent Test**: Can be fully tested by creating a fresh Phoenix project, adding `jido_murmur` as a dependency, running the migration generator, defining one agent profile, and verifying that messages can be sent, streamed, and persisted via the Runner and PubSub.

**Acceptance Scenarios**:

1. **Given** a new Phoenix project with `jido_murmur` added as a dependency, **When** the developer runs the install generator, **Then** database migration files are created in the consumer's repo migrations directory
2. **Given** the generated migrations have been run and the package is configured with Repo/PubSub/Jido modules, **When** the developer defines an agent using `use Jido.AI.Agent` with `jido_murmur` plugins and tools, **Then** the agent starts successfully and can process messages through the Runner
3. **Given** a running agent with StreamingPlugin enabled, **When** a message is sent, **Then** streaming signals are broadcast as native `Jido.Signal` structs on the configured PubSub
4. **Given** a running workspace with multiple agents, **When** one agent uses TellAction to message another, **Then** the target agent receives and processes the message via the PendingQueue

---

### User Story 2 - Consumer Uses Jido Directly Alongside jido_murmur (Priority: P1)

A developer who is experienced with Jido uses `jido_murmur` plugins and helpers for common operations, but also calls Jido APIs directly for advanced features — inspecting agent state, writing custom plugins, implementing alternative storage adapters — without the package interfering.

**Why this priority**: This validates the core design principle. If the package wraps or hides Jido in any way, the entire architecture is wrong. Jido interplay must work seamlessly.

**Independent Test**: Can be tested by adding a custom `Jido.Plugin` alongside `jido_murmur` plugins in an agent's plugin list, calling `Jido.AgentServer.state/1` directly on a running agent, and verifying both custom and package-provided components work together.

**Acceptance Scenarios**:

1. **Given** an agent definition with both `jido_murmur` plugins and a custom `Jido.Plugin`, **When** a signal is processed, **Then** both the package plugin and the custom plugin handle it correctly
2. **Given** a running agent started via AgentHelper, **When** the developer calls `Jido.AgentServer.state(pid)` directly, **Then** the full Jido agent state is returned without any wrapping or transformation
3. **Given** a consumer who implements `Jido.Storage` for a non-Ecto backend, **When** they configure their agent to use it instead of `JidoMurmur.Storage.Ecto`, **Then** the Runner and all orchestration logic work correctly with the alternative storage

---

### User Story 3 - Consumer Adds UI with jido_murmur_web Components (Priority: P2)

A developer adds `jido_murmur_web` to get pre-built LiveView components for chat, streaming indicators, and artifact display. They can either import components directly or use the generator to copy them into their project for full customization.

**Why this priority**: The web layer is important for rapid prototyping but is fully optional — consumers can build their own frontend using only the backend APIs from `jido_murmur`.

**Independent Test**: Can be tested by adding `jido_murmur_web` as a dependency, importing chat components into a LiveView, and verifying that messages render with streaming indicators.

**Acceptance Scenarios**:

1. **Given** `jido_murmur_web` is installed, **When** the developer imports and uses `ChatMessage` and `ChatStream` components in a LiveView, **Then** messages are rendered with proper styling and streaming state
2. **Given** the developer runs the install generator with a specific component group, **When** the generator completes, **Then** component source files are copied into the consumer's project and can be freely modified
3. **Given** a consumer using the ArtifactPanel component, **When** an artifact signal arrives, **Then** the panel dispatches to the configured renderer or falls back to a generic renderer

---

### User Story 4 - Consumer Adds Domain-Specific Tools from Plugin Packages (Priority: P2)

A developer adds `jido_tasks` to give their agents task management capabilities. They add the tool actions to their agent's tools list (standard Jido composition) and run the migration generator for the tasks table.

**Why this priority**: Plugin packages demonstrate the extensibility model and validate that domain-specific tools compose cleanly with the core package through standard Jido mechanisms.

**Independent Test**: Can be tested by adding `jido_tasks`, running the migration generator, adding task tools to an agent's tools list, and verifying the agent can create, update, and list tasks.

**Acceptance Scenarios**:

1. **Given** `jido_tasks` is installed and migrations are run, **When** the developer adds `JidoTasks.Tools.AddTask` to an agent's tools list, **Then** the agent can create tasks via the standard Jido action execution flow
2. **Given** an agent with task and arxiv tools from different plugin packages, **When** the agent processes a request that requires both, **Then** both sets of tools execute correctly without conflicts

---

### User Story 5 - Consumer Composes Multiple Request Transformers (Priority: P3)

A developer who needs custom request transformation (e.g., audit logging, context injection) alongside `MessageInjector` uses the `ComposableRequestTransformer` to chain multiple transformers in sequence.

**Why this priority**: Multi-transformer composition is an advanced feature that enables extensibility without requiring upstream Jido changes. Most consumers will use only the default `MessageInjector`.

**Independent Test**: Can be tested by defining two request transformers, composing them via `ComposableRequestTransformer`, and verifying both transformers' modifications appear in the final request.

**Acceptance Scenarios**:

1. **Given** an agent configured with `ComposableRequestTransformer` containing `MessageInjector` and a custom transformer, **When** a request is processed, **Then** both transformers apply their modifications in sequence with deep-merged overrides
2. **Given** one transformer in the chain returns an error, **When** the composed transformer processes the request, **Then** the chain halts and the error propagates

---

### User Story 6 - Existing Murmur Demo App Runs on the Umbrella Packages (Priority: P1)

The current Murmur application continues to function as a demo/reference app within the umbrella, depending on all extracted packages via umbrella dependencies. All existing features work unchanged.

**Why this priority**: The demo app validates that the extraction preserves all functionality. If the demo breaks, the extraction is incomplete or incorrect.

**Independent Test**: Can be tested by running the full existing test suite from the umbrella root and verifying all tests pass.

**Acceptance Scenarios**:

1. **Given** the umbrella project with murmur_demo depending on sibling packages, **When** `mix test` is run from the umbrella root, **Then** all existing tests pass without modification
2. **Given** the demo app running in development, **When** a user interacts with the workspace (create workspace, add agents, send messages, view artifacts), **Then** all features work identically to the pre-extraction application

---

### Edge Cases

- What happens when a consumer configures a Repo module that doesn't implement expected Ecto.Repo callbacks? The system should fail with a clear error at startup.
- What happens when a consumer runs `jido_murmur` migration generators multiple times? Subsequent runs should detect existing migrations and skip or warn.
- What happens when a plugin package's migrations run before `jido_murmur` migrations (e.g., tasks table referencing workspaces)? Migration generators must enforce correct ordering via timestamps and documentation.
- What happens when two ETS tables with the same name are created in a multi-app BEAM node? Table names must be namespaced to prevent collisions.
- What happens when the consumer does not configure an `authorize` hook but workspaces have `owner_id` set? The system should operate in permissive mode (no authorization checks) by default.
- What happens when a consumer upgrades the package but doesn't run new migrations? Database access should fail gracefully with an informative error rather than a cryptic crash.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide an installable core package (`jido_murmur`) containing all backend orchestration components (Runner, PendingQueue, MessageInjector, TeamInstructions, StreamingPlugin, ArtifactPlugin, TellAction, Storage.Ecto, Catalog, UITurn, AgentHelper)
- **FR-002**: The system MUST allow consumer projects to configure application-specific modules (Repo, PubSub, Jido bootstrap module) via application environment configuration
- **FR-003**: All Jido components (plugins, actions, storage adapters, request transformers) MUST implement their respective Jido behaviours directly without wrapper behaviours or abstraction layers
- **FR-004**: The system MUST return native Jido types (pids, Signal structs, Thread entries) from all public APIs without wrapping or transforming them
- **FR-005**: The system MUST provide migration generators that create timestamped Ecto migration files in the consumer's project for all required database tables
- **FR-006**: The system MUST provide a Catalog module that discovers agent profiles from application configuration rather than hardcoded module lists
- **FR-007**: The system MUST provide a `ComposableRequestTransformer` that chains multiple `ReAct.RequestTransformer` implementations in sequence with deep-merged overrides
- **FR-008**: The system MUST provide an `AgentHelper` module with convenience functions for common agent operations (starting agents, loading messages, loading artifacts, subscribing to PubSub topics) that return Jido-native types
- **FR-009**: The system MUST provide an optional web component package (`jido_murmur_web`) containing reusable LiveView components for chat, streaming, and artifact display
- **FR-010**: The web component package MUST offer both direct-import and generator-based installation modes for all components
- **FR-011**: The system MUST provide independently publishable tool packages (`jido_tasks`, `jido_arxiv`) that ship `Jido.Action` modules consumers add to their agents' tools lists
- **FR-012**: All database schemas MUST include an optional `owner_id` field and a `metadata` JSONB field to support future authentication and lightweight extensibility
- **FR-013**: The system MUST provide a pluggable authorization hook (defaulting to no-op) for workspace and session access control
- **FR-014**: The system MUST support artifact rendering via a configurable registry that maps artifact types to renderer component modules
- **FR-015**: The system MUST NOT impose a maximum number of agents per workspace — consumers decide their own limits
- **FR-016**: The system MUST provide a supervision tree component (`JidoMurmur.Supervisor`) that consumers add to their application's supervision tree
- **FR-017**: PubSub broadcasts MUST carry native `Jido.Signal` structs to preserve full signal information for consumer-side pattern matching
- **FR-018**: The umbrella project MUST maintain the existing Murmur application as a demo/reference app that depends on all extracted packages
- **FR-019**: Each package MUST ship with its own test suite containing both unit tests (individual module isolation with mocked dependencies) and integration tests (cross-component flow validation within the package)
- **FR-020**: Tests MUST NOT make third-party LLM API calls; all LLM interactions MUST be stubbed or mocked via the LLM adapter behaviour
- **FR-021**: The system MUST ship a built-in mock LLM adapter (`LLM.Mock`) that returns configurable canned responses for test use, while also supporting Mox-based stubs against the LLM behaviour for fine-grained test control
- **FR-022**: The system MUST emit `:telemetry` events at key lifecycle points (agent start/stop, message sent, streaming signal emitted, artifact stored) following Elixir ecosystem conventions, enabling consumers to attach their own handlers for metrics and logging
- **FR-023**: Each package with database dependencies MUST ship its own test case module with Ecto sandbox setup, sharing a single test database across the umbrella while remaining independently testable via `mix test --app <package_name>`
- **FR-024**: Each package MUST achieve a minimum of 80% line coverage before being published to Hex, measured per-package (not umbrella-wide)

### Key Entities

- **Package**: An independently publishable Hex package within the umbrella (jido_murmur, jido_murmur_web, jido_tasks, jido_arxiv). Each has its own mix.exs, dependencies, and test suite
- **Workspace**: A collaboration space containing one or more agent sessions. Key attributes: name, optional owner_id for future auth, metadata map for lightweight extensions
- **Agent Session**: A running agent instance within a workspace. Links a workspace to a specific agent profile. Key attributes: session identity, workspace reference, agent module reference
- **Agent Profile**: A module implementing `use Jido.AI.Agent` with an optional `catalog_meta/0` function for UI metadata. Registered via application configuration
- **Runner**: The orchestration engine that manages message sending, queuing (via PendingQueue), and LLM interactions for agents
- **Plugin**: A pre-built `Jido.Plugin` module (StreamingPlugin, ArtifactPlugin) that consumers add to their agent's plugins list for signal handling
- **Tool Action**: A pre-built `Jido.Action` module (TellAction, AddTask, ArxivSearch) that consumers add to their agent's tools list
- **LiveView Component**: A reusable Phoenix.Component module for chat messages, streaming indicators, artifact panels, etc. Consumers may import directly or copy via generator

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A new consumer project can install `jido_murmur`, configure it, define one agent, and send a message through the Runner with streaming responses in under 30 minutes of setup time
- **SC-002**: All existing Murmur test suites pass without modification when run from the umbrella root after extraction
- **SC-003**: Consumers can add custom `Jido.Plugin` and `Jido.Action` modules alongside package-provided ones with zero package-specific configuration — standard Jido composition only
- **SC-004**: Each package (jido_murmur, jido_murmur_web, jido_tasks, jido_arxiv) can be published independently to Hex and installed in isolation by consumers who only need that specific functionality
- **SC-005**: The `jido_murmur` package introduces zero wrapper behaviours that duplicate existing Jido behaviours — all components implement Jido interfaces directly
- **SC-006**: A consumer who knows Jido but has never seen jido_murmur can read any package source file and immediately recognize standard Jido patterns
- **SC-007**: Generator-installed LiveView components can be customized by the consumer without risk of being overwritten on package upgrades
- **SC-008**: The authorization hook can be added to an existing deployment through configuration change and a data migration (populating owner_id) without schema redesign
- **SC-009**: Each package achieves at least 80% line coverage with zero third-party LLM API calls in the test suite

## Clarifications

### Session 2026-03-28

- Q: What level of test coverage is required per package? → A: Unit + Integration tests — isolated module tests plus cross-component flow tests per package
- Q: What LLM mock/stub strategy should the package ship for tests? → A: Built-in mock adapter + Mox support — ship a configurable LLM.Mock that returns canned responses, plus Mox compatibility for custom stubs
- Q: Should the package emit telemetry events for observability? → A: Yes — emit :telemetry events at key lifecycle points (agent start/stop, message sent, streaming signal, artifact stored)
- Q: How should test database isolation work across packages in the umbrella? → A: Per-package test helpers with shared DB — each package ships its own TestCase module with Ecto sandbox checkout; single shared test database; packages independently testable
- Q: What minimum test coverage is required per package before Hex publishing? → A: 80% line coverage minimum per package as a publishing gate

## Assumptions

- Consumers are building Elixir/Phoenix applications and are familiar with the Jido framework ecosystem (jido, jido_ai, jido_signal, jido_action)
- Consumers use Ecto with PostgreSQL for persistence (the default storage adapter targets Ecto/Postgres; alternative storage implementations are the consumer's responsibility)
- The Jido framework maintains backward compatibility within major versions, allowing loose version pinning (~> 2.0)
- Authentication and multi-tenancy are out of scope for the initial release; the schema design is auth-ready but auth implementation is deferred
- The existing Murmur application's full feature set (workspace management, multi-agent chat, artifact rendering, task management, arXiv search) represents the validation baseline for the extraction
- LiveView components use Tailwind CSS classes; consumers using the direct-import mode must add `@source` directives for the package paths in their CSS configuration
- Each package starts at version 0.x.y to signal API instability during early development
- The `jido_arxiv` package is a lower priority (P2) and may be extracted after the core packages are stable
