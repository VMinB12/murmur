# Murmur → Modular Hex Packages: Refactoring Plan

## Executive Summary

This document maps out the extraction of Murmur's multi-agent architecture into reusable Hex packages. The goal is to allow other projects to build multi-agent applications by depending on these packages and focusing only on their own agents, tools, and frontend — while the core orchestration, persistence, and collaboration mechanisms are maintained in shared libraries.

---

## 1. Current Architecture Analysis

### 1.1 Module Map

```
murmur/
├── Murmur.Application          # OTP supervision tree
├── Murmur.Repo                 # Ecto repository
├── Murmur.Jido                 # Jido framework bootstrap (use Jido)
│
├── Murmur.Agents               # ← CORE ORCHESTRATION (extract target)
│   ├── Runner                  # Ask/await drain-loop, message queuing
│   ├── PendingQueue            # ETS-backed message queue
│   ├── TableOwner              # ETS table lifecycle
│   ├── MessageInjector         # ReAct request transformer
│   ├── TeamInstructions        # Dynamic multi-agent prompt builder
│   ├── StreamingPlugin         # Signal → PubSub forwarder
│   ├── ArtifactPlugin          # Artifact signal handler + persistence
│   ├── Artifact                # Artifact signal helper
│   ├── Actions.StoreArtifact   # Artifact state persistence action
│   ├── TellAction              # Inter-agent messaging (fire-and-forget)
│   ├── Catalog                 # Profile registry + color palette
│   ├── UITurn                  # Thread → display message projection
│   ├── LLM                     # LLM adapter behaviour
│   └── LLM.Real               # Production LLM adapter
│
├── Murmur.Agents.Profiles      # ← APP-SPECIFIC AGENTS
│   ├── GeneralAgent            # General-purpose assistant
│   └── ArxivAgent              # Academic paper researcher
│
├── Murmur.Agents.Tools         # ← MIXED (some reusable, some app-specific)
│   ├── AddTask                 # Task management tool (reusable)
│   ├── UpdateTask              # Task management tool (reusable)
│   ├── ListTasks               # Task management tool (reusable)
│   ├── ArxivSearch             # arXiv paper search (reusable plugin)
│   └── DisplayPaper            # Paper display tool (reusable plugin)
│
├── Murmur.Storage              # ← STORAGE ADAPTER (extract target)
│   ├── Ecto                    # Jido.Storage implementation
│   ├── Checkpoint              # Ecto schema
│   └── ThreadEntry             # Ecto schema
│
├── Murmur.Workspaces           # ← WORKSPACE MANAGEMENT (extract target)
│   ├── Workspace               # Ecto schema
│   └── AgentSession            # Ecto schema
│
├── Murmur.Tasks                # ← TASK MANAGEMENT (extract target)
│   └── Task                    # Ecto schema
│
└── MurmurWeb                   # ← WEB LAYER (stays in app, BUT extract LiveView components)
    ├── WorkspaceLive           # Main workspace UI (heavy coupling!)
    ├── WorkspaceListLive       # Workspace listing
    ├── Components.Artifacts    # Artifact rendering
    └── ...
```

### 1.2 Dependency Flow (Current)

```
MurmurWeb.WorkspaceLive
    ├── Murmur.Agents.Runner
    ├── Murmur.Agents.Catalog
    ├── Murmur.Agents.StreamingPlugin
    ├── Murmur.Agents.Artifact
    ├── Murmur.Agents.UITurn
    ├── Murmur.Workspaces
    ├── Murmur.Tasks
    ├── Murmur.Jido (start_agent, stop_agent, whereis, thaw, hibernate, __jido_storage__)
    ├── Jido.AgentServer (direct state access!)
    └── Jido.Signal.ID

Murmur.Agents.Runner
    ├── Murmur.Agents.Catalog
    ├── Murmur.Agents.PendingQueue
    ├── Murmur.Agents.LLM (behaviour)
    ├── Murmur.Jido
    └── Phoenix.PubSub

Murmur.Agents.TellAction
    ├── Murmur.Agents.Runner
    ├── Murmur.Workspaces
    └── Phoenix.PubSub
```

### 1.3 Key Observations

1. **WorkspaceLive is a god module** — it directly accesses agent internals (`Jido.AgentServer.state(pid)`), storage adapters, and manages agent lifecycle. This is the #1 coupling problem.

2. **The orchestration layer (Runner, PendingQueue, MessageInjector, etc.) is app-agnostic** — nothing in these modules is specific to Murmur's domain. They implement general multi-agent patterns.

3. **Plugins are already well-isolated** — StreamingPlugin and ArtifactPlugin follow the Jido.Plugin behaviour and have clean contracts.

4. **Storage adapter is fully generic** — `Murmur.Storage.Ecto` implements `Jido.Storage` with no app-specific logic.

5. **Workspace/Session management is semi-generic** — the concept of "workspaces containing agent sessions" is reusable, but the max-8-agents constraint and specific field names are domain choices.

6. **Task management tools are reusable** — AddTask/UpdateTask/ListTasks implement a Kanban-style task board that any multi-agent app could use.

7. **ArxivSearch/DisplayPaper are domain-specific but reusable** — they're self-contained tools that could be a plugin package.

---

## 2. Proposed Package Architecture

### 2.1 Package Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Consumer Application                      │
│  (e.g., murmur, project-x, project-y)                      │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ App Agents   │  │ App Frontend │  │ App Business     │  │
│  │ (profiles,   │  │ (LiveViews,  │  │ Logic            │  │
│  │  tools)      │  │  templates)  │  │                  │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────────────┘  │
│         │                  │                                 │
│  ┌──────┴──────────────────┴─────────────────────────────┐  │
│  │              jido_workbench (core package)             │  │
│  │  Runner · PendingQueue · TeamInstructions · Catalog    │  │
│  │  StreamingPlugin · ArtifactPlugin · TellAction         │  │
│  │  UITurn · MessageInjector · LLM adapter               │  │
│  │  Workspace/Session management · Storage adapter        │  │
│  │  LiveView components (chat, artifacts, task board)     │  │
│  └───────────────────────┬───────────────────────────────┘  │
│                          │                                   │
│  ┌───────────────────────┴───────────────────────────────┐  │
│  │              jido ecosystem (existing)                  │  │
│  │  jido · jido_ai · jido_signal · jido_action · req_llm │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │            Optional Plugin Packages                  │    │
│  │  jido_tasks_plugin · jido_arxiv_plugin · ...        │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Package Definitions

#### Package 1: `jido_workbench` (Core Multi-Agent Architecture)

**Purpose:** Everything needed to build a multi-agent workspace application.

**Contains:**
- Agent orchestration (Runner, PendingQueue, TableOwner, MessageInjector)
- Team collaboration (TeamInstructions, TellAction)
- Signal streaming (StreamingPlugin)
- Artifact management (ArtifactPlugin, Artifact, StoreArtifact)
- Agent catalog/registry (Catalog)
- UI projection (UITurn)
- LLM adapter behaviour
- Workspace/Session management (schemas, context, migrations)
- Storage adapter (Ecto implementation of Jido.Storage)
- Reusable LiveView components and helpers

**Dependencies:**
- `jido`, `jido_ai`, `jido_signal`, `jido_action`, `req_llm`
- `phoenix`, `phoenix_live_view`, `phoenix_ecto`, `ecto_sql`, `postgrex`
- `phoenix_pubsub`, `jason`

---

#### Package 2: `jido_tasks_plugin` (Task Management Plugin)

**Purpose:** Kanban-style task board for multi-agent collaboration.

**Contains:**
- Task schema + migrations
- Task context (CRUD, filtering, stats)
- Task tools (AddTask, UpdateTask, ListTasks)
- TaskBoard LiveView component

**Dependencies:**
- `jido_workbench`, `jido_action`, `ecto_sql`

---

#### Package 3: `jido_arxiv_plugin` (Academic Research Plugin)

**Purpose:** arXiv paper search and display for research-oriented agents.

**Contains:**
- ArxivSearch tool
- DisplayPaper tool
- PaperList component
- PdfViewer component

**Dependencies:**
- `jido_workbench` (for Artifact), `jido_action`, `req`, `sweet_xml`

---

#### Future Plugin Packages (examples):
- `jido_web_search_plugin` — Web search tool
- `jido_code_plugin` — Code execution/analysis tools
- `jido_calendar_plugin` — Calendar/scheduling tools
- `jido_email_plugin` — Email drafting/sending tools

---

## 3. Detailed Extraction Plan: `jido_workbench`

### 3.1 Module Mapping

| Current Module | New Module | Notes |
|---|---|---|
| `Murmur.Agents.Runner` | `JidoWorkbench.Runner` | Core orchestration |
| `Murmur.Agents.PendingQueue` | `JidoWorkbench.PendingQueue` | ETS message queue |
| `Murmur.Agents.TableOwner` | `JidoWorkbench.TableOwner` | ETS lifecycle |
| `Murmur.Agents.MessageInjector` | `JidoWorkbench.MessageInjector` | Request transformer |
| `Murmur.Agents.TeamInstructions` | `JidoWorkbench.TeamInstructions` | Collaboration prompt |
| `Murmur.Agents.StreamingPlugin` | `JidoWorkbench.StreamingPlugin` | Signal forwarder |
| `Murmur.Agents.ArtifactPlugin` | `JidoWorkbench.ArtifactPlugin` | Artifact handler |
| `Murmur.Agents.Artifact` | `JidoWorkbench.Artifact` | Artifact helpers |
| `Murmur.Agents.Actions.StoreArtifact` | `JidoWorkbench.Actions.StoreArtifact` | Artifact persistence |
| `Murmur.Agents.TellAction` | `JidoWorkbench.TellAction` | Inter-agent comms |
| `Murmur.Agents.Catalog` | `JidoWorkbench.Catalog` | Profile registry |
| `Murmur.Agents.UITurn` | `JidoWorkbench.UITurn` | Thread → UI projection |
| `Murmur.Agents.LLM` | `JidoWorkbench.LLM` | Adapter behaviour |
| `Murmur.Agents.LLM.Real` | `JidoWorkbench.LLM.Real` | Production adapter |
| `Murmur.Storage.Ecto` | `JidoWorkbench.Storage.Ecto` | Jido.Storage impl |
| `Murmur.Storage.Checkpoint` | `JidoWorkbench.Storage.Checkpoint` | Schema |
| `Murmur.Storage.ThreadEntry` | `JidoWorkbench.Storage.ThreadEntry` | Schema |
| `Murmur.Workspaces` | `JidoWorkbench.Workspaces` | Context |
| `Murmur.Workspaces.Workspace` | `JidoWorkbench.Workspaces.Workspace` | Schema |
| `Murmur.Workspaces.AgentSession` | `JidoWorkbench.Workspaces.AgentSession` | Schema |
| `Murmur.Jido` | *Consumer defines* | `use Jido` stays in app |
| `Murmur.Repo` | *Consumer defines* | Ecto.Repo stays in app |

### 3.2 Critical Abstractions to Introduce

#### 3.2.1 Configuration Module

The package needs a way to access the consuming application's Repo and Jido modules without hardcoding them.

```elixir
# In jido_workbench
defmodule JidoWorkbench do
  @moduledoc "Configuration for JidoWorkbench"

  def repo do
    Application.fetch_env!(:jido_workbench, :repo)
  end

  def jido do
    Application.fetch_env!(:jido_workbench, :jido)
  end

  def pubsub do
    Application.fetch_env!(:jido_workbench, :pubsub)
  end

  def otp_app do
    Application.fetch_env!(:jido_workbench, :otp_app)
  end
end
```

Consumer configures in `config.exs`:
```elixir
config :jido_workbench,
  repo: MyApp.Repo,
  jido: MyApp.Jido,
  pubsub: MyApp.PubSub,
  otp_app: :my_app
```

#### 3.2.2 Agent Profile Behaviour

Currently profiles (GeneralAgent, ArxivAgent) are hardcoded in the Catalog. We need a behaviour that consumer apps implement.

```elixir
defmodule JidoWorkbench.AgentProfile do
  @moduledoc "Behaviour for defining agent profiles for the catalog"

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback catalog_meta() :: %{color: String.t()}

  # The profile module itself is a Jido.AI.Agent, so it already
  # defines tools, plugins, system_prompt, model, etc.
end
```

Catalog becomes configuration-driven:
```elixir
config :jido_workbench,
  profiles: [
    MyApp.Agents.CustomerSupportAgent,
    MyApp.Agents.BillingAgent,
    MyApp.Agents.TechSupportAgent
  ]
```

#### 3.2.3 Workspace Facade (Decoupling WorkspaceLive)

The biggest refactoring target is `WorkspaceLive`, which directly accesses agent internals. We need a facade that encapsulates all agent state access.

```elixir
defmodule JidoWorkbench.WorkspaceFacade do
  @moduledoc """
  High-level API for workspace operations.
  Encapsulates agent lifecycle, message loading, and artifact access
  so that LiveViews never touch agent internals directly.
  """

  @doc "Start or restore an agent for a session"
  @spec ensure_agent_started(AgentSession.t()) :: {:ok, pid()} | {:error, term()}
  def ensure_agent_started(session)

  @doc "Load formatted messages for a session"
  @spec load_messages(AgentSession.t()) :: [UITurn.t()]
  def load_messages(session)

  @doc "Load artifacts for a session"
  @spec load_artifacts(AgentSession.t()) :: %{String.t() => term()}
  def load_artifacts(session)

  @doc "Send a message to an agent"
  @spec send_message(AgentSession.t(), String.t()) :: :queued | :agent_not_running
  def send_message(session, content)

  @doc "Clean up all storage for a workspace"
  @spec cleanup_workspace(workspace_id :: String.t()) :: :ok
  def cleanup_workspace(workspace_id)

  @doc "Subscribe to all relevant PubSub topics for a session"
  @spec subscribe(workspace_id :: String.t(), session_id :: String.t()) :: :ok
  def subscribe(workspace_id, session_id)

  @doc "Stop an agent and clean its storage"
  @spec stop_and_cleanup(AgentSession.t()) :: :ok
  def stop_and_cleanup(session)
end
```

This eliminates the need for LiveViews to call:
- `Jido.AgentServer.state(pid)` (internal state access)
- `Murmur.Jido.__jido_storage__()` (storage adapter access)
- `Murmur.Jido.start_agent/stop_agent/whereis/thaw` (lifecycle)

#### 3.2.4 Plugin Registration System

Plugins like `jido_tasks_plugin` need to register themselves with the workbench:

```elixir
defmodule JidoWorkbench.PluginRegistry do
  @moduledoc """
  Registry for workbench plugins that contribute:
  - Tools (Jido.Action modules)
  - Jido Plugins (signal handlers)
  - LiveView artifact components
  - Database migrations
  """

  @callback tools() :: [module()]
  @callback plugins() :: [module()]
  @callback artifact_renderers() :: %{String.t() => module()}
  @callback migrations_path() :: String.t()
end
```

#### 3.2.5 Artifact Renderer Behaviour

Currently artifact rendering is hardcoded to dispatch on artifact name:
```elixir
# Current: hardcoded in artifacts.ex
case artifact_name do
  "papers" -> PaperList
  "displayed_paper" -> PdfViewer
  _ -> Generic
end
```

This should be a configurable registry:
```elixir
defmodule JidoWorkbench.ArtifactRenderer do
  @callback badge(assigns :: map()) :: Phoenix.LiveView.Rendered.t()
  @callback detail(assigns :: map()) :: Phoenix.LiveView.Rendered.t()
end
```

Consumer or plugins register renderers:
```elixir
config :jido_workbench,
  artifact_renderers: %{
    "papers" => JidoArxivPlugin.Components.PaperList,
    "displayed_paper" => JidoArxivPlugin.Components.PdfViewer,
    "task_board" => JidoTasksPlugin.Components.TaskBoard
  }
```

### 3.3 Migration Strategy

#### Database Migrations

`jido_workbench` should ship migration modules that consumers install into their app:

```elixir
# Consumer runs:
mix jido_workbench.install

# This generates into the consumer's priv/repo/migrations/:
# - TIMESTAMP_create_jido_workbench_workspaces.exs
# - TIMESTAMP_create_jido_workbench_agent_sessions.exs
# - TIMESTAMP_create_jido_workbench_checkpoints.exs
# - TIMESTAMP_create_jido_workbench_thread_entries.exs
```

Alternatively, use Ecto's `@migration_source` or provide migration templates that the consumer can customize.

For plugin packages (e.g., `jido_tasks_plugin`):
```elixir
mix jido_tasks_plugin.install
# Generates: TIMESTAMP_create_jido_tasks.exs
```

### 3.4 PubSub Topic Contracts

These are the stable PubSub contracts that LiveViews and other consumers depend on:

| Topic Pattern | Message | Source |
|---|---|---|
| `"workspace:#{workspace_id}"` | `{:new_message, session_id, msg}` | Runner, TellAction |
| `"agent_stream:#{session_id}"` | `{:agent_signal, session_id, signal}` | StreamingPlugin |
| `"agent_artifacts:#{session_id}"` | `{:artifact_update, session_id, name, data, mode}` | ArtifactPlugin |
| `"tasks:#{workspace_id}"` | `{:task_created, task}`, `{:task_updated, task}` | Tasks context |

These topic patterns and message shapes MUST be documented and versioned as part of the public API.

### 3.5 Supervision Tree

The workbench needs to be startable as part of the consumer's supervision tree:

```elixir
# Consumer's application.ex
children = [
  MyApp.Repo,
  {Phoenix.PubSub, name: MyApp.PubSub},
  {JidoWorkbench.Supervisor, []},  # ← Starts TableOwner, etc.
  MyAppWeb.Endpoint,
  MyApp.Jido
]
```

`JidoWorkbench.Supervisor` manages:
- `JidoWorkbench.TableOwner` (ETS tables)
- Any future workbench-specific processes

---

## 4. Detailed Extraction Plan: Plugin Packages

### 4.1 `jido_tasks_plugin`

```
jido_tasks_plugin/
├── lib/
│   ├── jido_tasks_plugin.ex              # Plugin registration
│   ├── jido_tasks_plugin/
│   │   ├── task.ex                       # Ecto schema
│   │   ├── tasks.ex                      # Context (CRUD)
│   │   ├── tools/
│   │   │   ├── add_task.ex              # Jido.Action
│   │   │   ├── update_task.ex           # Jido.Action
│   │   │   └── list_tasks.ex            # Jido.Action
│   │   └── components/
│   │       └── task_board.ex            # LiveView component
├── priv/
│   └── templates/
│       └── create_tasks_migration.exs   # Migration template
└── mix.exs
```

**Usage in consumer agent:**
```elixir
defmodule MyApp.Agents.ProjectManager do
  use Jido.AI.Agent,
    name: "project_manager",
    description: "Manages team tasks and tracks progress",
    tools: [
      JidoTasksPlugin.Tools.AddTask,
      JidoTasksPlugin.Tools.UpdateTask,
      JidoTasksPlugin.Tools.ListTasks,
      JidoWorkbench.TellAction
    ],
    plugins: [
      JidoWorkbench.StreamingPlugin,
      JidoWorkbench.ArtifactPlugin
    ],
    request_transformer: JidoWorkbench.MessageInjector,
    model: :fast,
    system_prompt: "You are a project manager..."
end
```

### 4.2 `jido_arxiv_plugin`

```
jido_arxiv_plugin/
├── lib/
│   ├── jido_arxiv_plugin.ex
│   ├── jido_arxiv_plugin/
│   │   ├── tools/
│   │   │   ├── arxiv_search.ex          # Jido.Action
│   │   │   └── display_paper.ex         # Jido.Action
│   │   └── components/
│   │       ├── paper_list.ex            # LiveView component
│   │       └── pdf_viewer.ex            # LiveView component
└── mix.exs
```

### 4.3 Plugin Contract

Every plugin package should implement:

```elixir
defmodule JidoWorkbench.Plugin do
  @moduledoc "Behaviour for workbench plugin packages"

  @doc "Jido.Action modules provided by this plugin"
  @callback tools() :: [module()]

  @doc "Jido.Plugin modules (signal handlers) provided"
  @callback jido_plugins() :: [module()]

  @doc "Map of artifact_name → renderer module"
  @callback artifact_renderers() :: %{String.t() => module()}

  @doc "Path to migration templates, or nil"
  @callback migrations_path() :: String.t() | nil

  @doc "PubSub topic patterns this plugin subscribes to"
  @callback pubsub_topics() :: [String.t()]
end
```

---

## 5. Architectural Boundaries & Stable Contracts

### 5.1 Contract Hierarchy

```
Level 0: Jido Ecosystem (jido, jido_ai, jido_action, jido_signal)
  ├── Jido.Storage behaviour
  ├── Jido.Action behaviour (run/2)
  ├── Jido.Plugin behaviour (handle_signal/2)
  ├── Jido.AI.Agent macro (agent definition)
  └── ReAct.RequestTransformer behaviour

Level 1: JidoWorkbench (core multi-agent architecture)
  ├── JidoWorkbench configuration contract
  ├── JidoWorkbench.AgentProfile behaviour
  ├── JidoWorkbench.ArtifactRenderer behaviour
  ├── JidoWorkbench.WorkspaceFacade API
  ├── JidoWorkbench.Plugin behaviour
  ├── PubSub topic/message contracts
  └── Database schema contracts (migrations)

Level 2: Plugin Packages (jido_tasks_plugin, jido_arxiv_plugin, etc.)
  ├── Implement JidoWorkbench.Plugin
  ├── Provide Jido.Action tools
  ├── Provide artifact renderers
  └── Provide migration templates

Level 3: Consumer Application (murmur, project-x, etc.)
  ├── Define Ecto.Repo and Jido bootstrap
  ├── Define agent profiles (implement AgentProfile)
  ├── Compose tools from plugins
  ├── Build custom LiveViews
  └── Configure workbench + plugins
```

### 5.2 Versioning Strategy

**Semantic Versioning with these rules:**

- **Patch (0.x.Y):** Bug fixes, performance improvements, no API changes
- **Minor (0.X.0):** New features, new optional configuration, backward-compatible changes
- **Major (X.0.0):** Breaking changes to any Level 1 contract

**Specific contracts that MUST NOT break without major version bump:**

1. `JidoWorkbench.WorkspaceFacade` public function signatures
2. `JidoWorkbench.AgentProfile` callback signatures
3. `JidoWorkbench.ArtifactRenderer` callback signatures
4. `JidoWorkbench.Plugin` callback signatures
5. PubSub topic patterns and message tuple shapes
6. Database table schemas (migrations should always be additive)
7. Configuration keys and expected value shapes

### 5.3 Boundary Enforcement

Use `boundary` or compile-time checks to enforce:

```
Consumer App
  ├── CAN depend on: JidoWorkbench public API, Plugin public APIs
  ├── CANNOT depend on: JidoWorkbench internal modules
  │
JidoWorkbench
  ├── CAN depend on: Jido ecosystem, Phoenix, Ecto
  ├── CANNOT depend on: Consumer app modules (use config/behaviours)
  │
Plugin Packages
  ├── CAN depend on: JidoWorkbench public API, Jido ecosystem
  ├── CANNOT depend on: Consumer app modules, other plugins
```

---

## 6. Refactoring Execution Plan

### Phase 1: Introduce Abstractions In-Place (1-2 weeks)

**Goal:** Create the abstraction boundaries within the existing Murmur codebase before extracting anything. This de-risks the extraction.

1. **Create WorkspaceFacade**
   - Extract all agent state access from `WorkspaceLive` into `Murmur.Agents.WorkspaceFacade`
   - Functions: `ensure_agent_started/1`, `load_messages/1`, `load_artifacts/1`, `send_message/2`, `cleanup_workspace/1`, `subscribe/2`
   - Update `WorkspaceLive` to use facade exclusively
   - **Test:** All existing LiveView tests pass without changes

2. **Create AgentProfile behaviour**
   - Define `Murmur.Agents.AgentProfile` behaviour
   - Update `GeneralAgent` and `ArxivAgent` to implement it
   - Make `Catalog` read profiles from application config instead of hardcoded list
   - **Test:** Catalog tests pass with configuration-driven profiles

3. **Create ArtifactRenderer behaviour**
   - Define renderer behaviour
   - Make artifact dispatch configurable
   - **Test:** Artifact rendering tests pass

4. **Parameterize hardcoded references**
   - Replace all `Murmur.Repo` references with configurable module
   - Replace all `Murmur.Jido` references with configurable module
   - Replace all `Murmur.PubSub` references with configurable module
   - **Test:** All tests pass with the same modules configured via application env

### Phase 2: Extract `jido_workbench` (1-2 weeks)

**Goal:** Move the abstracted modules into a separate Hex package.

1. **Create package skeleton**
   ```
   jido_workbench/
   ├── lib/jido_workbench.ex
   ├── lib/jido_workbench/
   ├── mix.exs
   ├── test/
   └── priv/templates/
   ```

2. **Move modules** (following the mapping in Section 3.1)
   - Core orchestration: Runner, PendingQueue, TableOwner, MessageInjector, TeamInstructions
   - Plugins: StreamingPlugin, ArtifactPlugin, Artifact, StoreArtifact
   - Communication: TellAction, LLM behaviour
   - UI: Catalog, UITurn
   - Storage: Ecto adapter, Checkpoint, ThreadEntry schemas
   - Workspaces: Workspace, AgentSession, Workspaces context
   - Behaviours: AgentProfile, ArtifactRenderer, Plugin
   - Facade: WorkspaceFacade

3. **Create migration generator**
   - `mix jido_workbench.install` task
   - Generates migration files into consumer's `priv/repo/migrations/`

4. **Create test helpers**
   - `JidoWorkbench.TestCase` — equivalent of current `AgentCase`
   - Mock LLM helpers for consumer tests

5. **Update Murmur to depend on `jido_workbench`**
   - Add `{:jido_workbench, path: "../jido_workbench"}` to deps
   - Update all module references
   - Remove extracted modules from Murmur
   - **Test:** All Murmur tests pass

### Phase 3: Extract Plugin Packages (1 week each)

1. **Extract `jido_tasks_plugin`**
   - Move Task schema, Tasks context, task tools, TaskBoard component
   - Create migration generator
   - Update Murmur to depend on it

2. **Extract `jido_arxiv_plugin`**
   - Move ArxivSearch, DisplayPaper tools, PaperList, PdfViewer components
   - Update Murmur to depend on it

### Phase 4: LiveView Component Library (1-2 weeks)

**Goal:** Ship reusable LiveView components in `jido_workbench` that provide:

1. **Chat components** (extracted from WorkspaceLive template)
   - `JidoWorkbench.Components.ChatMessage` — single message bubble
   - `JidoWorkbench.Components.ChatStream` — message list with streaming
   - `JidoWorkbench.Components.AgentHeader` — agent name/status header
   - `JidoWorkbench.Components.MessageInput` — message input form
   - `JidoWorkbench.Components.StreamingIndicator` — thinking/tool_call/usage display

2. **Workspace components**
   - `JidoWorkbench.Components.AgentSelector` — add agent to workspace
   - `JidoWorkbench.Components.WorkspaceList` — workspace listing
   - `JidoWorkbench.Components.ArtifactPanel` — artifact tab panel (with renderer dispatch)

3. **Layout helpers**
   - Split view (multiple agent columns)
   - Unified view (single timeline)

These components should be **opt-in** — consumers can use them directly or build their own UI while depending on the facade API.

### Phase 5: Validation & Documentation (1 week)

1. **Create a second consumer app** to validate the package works
   - Minimal app with 1 custom agent profile
   - Depends on `jido_workbench`
   - Should take < 1 hour to set up

2. **Write documentation**
   - Getting started guide
   - Agent profile creation guide
   - Plugin creation guide
   - API reference (ExDoc)
   - Architecture decision records

3. **Publish packages**
   - `jido_workbench` on Hex.pm
   - `jido_tasks_plugin` on Hex.pm
   - `jido_arxiv_plugin` on Hex.pm

---

## 7. Risks & Mitigations

### 7.1 Circular Dependencies

**Risk:** `TellAction` depends on `Workspaces` context, which depends on `Repo`. If `Repo` is in the consumer app, `TellAction` can't call it directly.

**Mitigation:** All database access goes through the configurable `repo()` function in `JidoWorkbench`. The consumer configures their Repo module at startup.

### 7.2 ETS Table Naming Conflicts

**Risk:** Multiple consumer apps running in the same BEAM node could conflict on ETS table names.

**Mitigation:** Namespace ETS tables with the OTP app name: `:jido_workbench_pending_messages` or use `{:via, Registry, {JidoWorkbench.Registry, :pending_messages}}`.

### 7.3 PubSub Name Conflicts

**Risk:** Hardcoded PubSub name won't work in multi-app deployments.

**Mitigation:** Already addressed — PubSub module is configurable via application env.

### 7.4 Migration Ordering

**Risk:** Plugin migrations depend on workbench migrations (e.g., tasks table references workspaces table).

**Mitigation:** Migration generator enforces ordering via timestamps. Document dependency chain in installation instructions.

### 7.5 LiveView Component Styling

**Risk:** Tailwind classes from the package may not be picked up by the consumer's CSS build.

**Mitigation:** Document the required `@source` directive in the consumer's `app.css`:
```css
@source "../../deps/jido_workbench";
@source "../../deps/jido_tasks_plugin";
```

### 7.6 Breaking Changes During Early Development

**Risk:** The API will inevitably change as we learn from the first few consumer apps.

**Mitigation:**
- Start at version `0.x.y` to signal instability
- Use `@deprecated` annotations before removing features
- Maintain a CHANGELOG with migration guides
- Consider a `JidoWorkbench.Compat` module for backward compatibility shims

---

## 8. Open Questions for Discussion

1. **Package naming:** Is `jido_workbench` the right name? Alternatives: `jido_workspace`, `jido_multi_agent`, `jido_collab`, `jido_studio`.

2. **Monorepo vs multi-repo:** Should `jido_workbench` and plugins live in the same GitHub repo (monorepo with `mix.exs` in subdirectories) or separate repos? Monorepo is easier for coordinated changes; multi-repo is better for independent versioning.

3. **LiveView components: opt-in or required?** Should the workbench ship with "batteries included" LiveView components, or should it be purely a backend package with consumers building their own UI?

4. **Workspace schema flexibility:** Should the workspace/session schemas be extensible (e.g., allow consumers to add custom fields)? Or should consumers wrap them with their own schemas that reference workbench schemas?

5. **Max agents per workspace:** Currently hardcoded to 8. Should this be configurable? Should it be enforced at the package level or left to consumers?

6. **Plugin discovery:** Should plugins be auto-discovered from deps, or explicitly registered in config? Auto-discovery is convenient but can be surprising.

7. **Authentication/authorization:** The current codebase has no auth. Should the workbench include hooks for authorization (e.g., "can this user access this workspace?") or leave it entirely to consumers?

8. **Multi-tenancy:** Some consumer apps may need multi-tenant workspaces. Should the workbench account for this in its schema design (e.g., optional `tenant_id` on workspaces)?

---

## 9. Summary of Deliverables

| Deliverable | Type | Priority |
|---|---|---|
| `jido_workbench` Hex package | Core package | P0 — Must have |
| WorkspaceFacade API | Abstraction | P0 — Must have |
| AgentProfile behaviour | Contract | P0 — Must have |
| ArtifactRenderer behaviour | Contract | P0 — Must have |
| Migration generators | Tooling | P0 — Must have |
| JidoWorkbench.Plugin behaviour | Contract | P1 — Should have |
| Reusable LiveView components | UI library | P1 — Should have |
| `jido_tasks_plugin` | Plugin package | P1 — Should have |
| `jido_arxiv_plugin` | Plugin package | P2 — Nice to have |
| Test helpers | DX | P1 — Should have |
| Getting Started guide | Documentation | P0 — Must have |
| Second consumer validation | Validation | P1 — Should have |

---

## Appendix A: Current Coupling Map

This diagram shows every module-to-module dependency in the current codebase, color-coded by extraction target:

```
🟦 = jido_workbench extraction target
🟩 = jido_tasks_plugin extraction target
🟪 = jido_arxiv_plugin extraction target
⬜ = stays in consumer app (Murmur)

⬜ MurmurWeb.WorkspaceLive
  → 🟦 Runner (send_message)
  → 🟦 Catalog (list_profiles, get_profile!, agent_color)
  → 🟦 StreamingPlugin (stream_topic)
  → 🟦 Artifact (artifact_topic)
  → 🟦 UITurn (project_entries)
  → 🟦 Workspaces (CRUD)
  → 🟩 Tasks (CRUD)
  → 🟦 Jido (start_agent, stop_agent, whereis, thaw, __jido_storage__)
  → ❌ Jido.AgentServer (SHOULD NOT access directly)

🟦 Runner
  → 🟦 Catalog (agent_module)
  → 🟦 PendingQueue (enqueue, drain, pending?)
  → 🟦 Jido (whereis, hibernate)
  → 🟦 LLM (ask, await)

🟦 TellAction
  → 🟦 Runner (send_message)
  → 🟦 Workspaces (find_agent_session_by_name)

🟦 MessageInjector
  → 🟦 PendingQueue (drain)
  → 🟦 TeamInstructions (build)

🟦 TeamInstructions
  → 🟦 Workspaces (list_agent_sessions)
  → 🟦 Catalog (get_profile!)

🟩 AddTask / UpdateTask / ListTasks
  → 🟩 Tasks (create_task, update_task, list_tasks)
  → 🟦 Runner (send_message) [for notifications]
  → 🟦 Workspaces (find_agent_session_by_name)

🟪 ArxivSearch
  → 🟦 Artifact (emit)

⬜ GeneralAgent / ArxivAgent
  → 🟦 TellAction, StreamingPlugin, ArtifactPlugin, MessageInjector
  → 🟩 AddTask, UpdateTask, ListTasks
  → 🟪 ArxivSearch, DisplayPaper
```

## Appendix B: Consumer App Skeleton

After extraction, a new consumer project would look like:

```
my_agent_app/
├── lib/
│   ├── my_agent_app/
│   │   ├── application.ex          # Start Repo, PubSub, Workbench, Jido
│   │   ├── repo.ex                 # Ecto.Repo
│   │   ├── jido.ex                 # use Jido, otp_app: :my_agent_app
│   │   └── agents/
│   │       ├── customer_support.ex # use Jido.AI.Agent + tools
│   │       └── billing_agent.ex    # use Jido.AI.Agent + tools
│   ├── my_agent_app_web/
│   │   ├── live/
│   │   │   └── workspace_live.ex   # Uses JidoWorkbench components or custom UI
│   │   └── router.ex
├── config/
│   └── config.exs                  # Configure jido_workbench
├── mix.exs                         # Depends on jido_workbench, jido_tasks_plugin
└── priv/
    └── repo/migrations/            # Generated by mix jido_workbench.install
```

**mix.exs:**
```elixir
defp deps do
  [
    {:jido_workbench, "~> 0.1"},
    {:jido_tasks_plugin, "~> 0.1"},
    {:phoenix, "~> 1.8"},
    {:phoenix_live_view, "~> 1.1"},
    ...
  ]
end
```

**config.exs:**
```elixir
config :jido_workbench,
  repo: MyAgentApp.Repo,
  jido: MyAgentApp.Jido,
  pubsub: MyAgentApp.PubSub,
  otp_app: :my_agent_app,
  profiles: [
    MyAgentApp.Agents.CustomerSupport,
    MyAgentApp.Agents.BillingAgent
  ],
  artifact_renderers: %{
    # custom renderers + plugin renderers
  }
```
