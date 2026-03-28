# Murmur → Modular Hex Packages: Refactoring Plan

## Executive Summary

This document maps out the extraction of Murmur's multi-agent architecture into reusable Hex packages. The goal is to allow other projects to build multi-agent applications by depending on these packages and focusing only on their own agents, tools, and frontend — while the core orchestration, persistence, and collaboration mechanisms are maintained in shared libraries.

**Critical design principle:** Our hex packages must **not** abstract away Jido. Consumer projects are Jido projects. The packages we extract provide **pre-built Jido components** (actions, plugins, storage adapters, LiveView helpers) that consumers compose using Jido's own APIs. Jido types (`Signal`, `Thread`, `Agent`, `Action`, `Plugin`) are first-class citizens throughout — never wrapped, never hidden. This ensures consumer projects can always reach down to Jido when they need to, and that improvements to Jido flow through to everyone seamlessly.

---

## 1. Design Philosophy: Jido-Native, Not Jido-Wrapping

### 1.1 The Anti-Pattern: Abstraction Walls

A naïve extraction would create wrapper behaviours that hide Jido:

```
Consumer App → JidoWorkbench wrapper API → Jido (hidden)
```

This is wrong because:
- Consumers **lose access** to Jido features not exposed by the wrapper
- Every new Jido feature requires a corresponding wrapper update
- Consumers can't use Jido documentation directly — they need workbench-specific docs
- Two parallel APIs to learn and maintain
- Breaks when Jido evolves (wrapper lags behind)

### 1.2 The Correct Pattern: Jido Extension

Our packages should sit **alongside** Jido, not on top of it:

```
Consumer App → Jido (direct)
             → JidoWorkbench (reusable Jido components)
             → Jido Plugins (reusable Jido actions/plugins)
```

**Concretely, this means:**

| Do This (Jido-Native) | Not This (Jido-Wrapping) |
|---|---|
| Consumers `use Jido.AI.Agent` directly | Don't create `JidoWorkbench.Agent` wrapper |
| Plugins implement `Jido.Plugin` directly | Don't create `JidoWorkbench.Plugin` wrapper behaviour |
| Tools implement `Jido.Action` directly | Don't create `JidoWorkbench.Action` wrapper |
| Storage adapters implement `Jido.Storage` directly | Don't create `JidoWorkbench.Storage` wrapper |
| PubSub broadcasts carry `Jido.Signal` structs | Don't strip signals into custom tuples |
| Consumers call `Jido.AgentServer.state(pid)` if they need agent state | Don't hide agent access behind a facade that prevents direct use |
| Consumer request transformers implement `Jido.AI.Reasoning.ReAct.RequestTransformer` | Don't wrap it in a workbench-specific behaviour |

### 1.3 What the Workbench Actually Provides

The workbench is a **collection of pre-built, reusable Jido components**:

1. **Ready-made Jido.Plugin modules** — StreamingPlugin, ArtifactPlugin (consumers add them to their agent's `plugins:` list)
2. **Ready-made Jido.Action modules** — TellAction, StoreArtifact (consumers add them to their agent's `tools:` list)
3. **A Jido.Storage adapter** — Ecto-backed persistence (consumers configure it in their `use Jido` call)
4. **A Jido.AI.Reasoning.ReAct.RequestTransformer** — MessageInjector (consumers set it as their agent's `request_transformer:`)
5. **Orchestration logic** — Runner, PendingQueue, TeamInstructions (consume Jido agents via standard Jido APIs)
6. **Ecto schemas & contexts** — Workspace, AgentSession, CRUD operations
7. **LiveView components** — Chat, artifacts, streaming indicators
8. **Convenience functions** — Helper functions that make common Jido operations easier, without preventing direct Jido access

### 1.4 The Jido Interplay Test

Every API decision should pass this test:

> "Can a consumer project that knows Jido well use Jido features directly alongside our package, without the package getting in the way?"

If the answer is no, the abstraction is wrong.

**Examples:**

✅ **Good:** Consumer writes a custom `Jido.Plugin` and adds it alongside `JidoWorkbench.StreamingPlugin` in their agent's plugin list — works seamlessly because we use Jido's native plugin system.

✅ **Good:** Consumer calls `Jido.AgentServer.state(pid)` to inspect agent internals for debugging — works because we don't hide the pid.

✅ **Good:** Consumer implements `Jido.Storage` for Redis instead of Ecto — works because we don't wrap the storage interface.

✅ **Good:** Consumer writes a custom `Jido.AI.Reasoning.ReAct.RequestTransformer` that composes with ours — works because we implement the standard Jido interface.

❌ **Bad:** Consumer wants to use a new Jido signal type but our `JidoWorkbench.Plugin` wrapper behaviour doesn't expose it — they're blocked until we update.

❌ **Bad:** Consumer has a `Jido.Thread` from the storage layer but our facade returns a custom struct — they have to convert back and forth.

---

## 2. Current Architecture Analysis

### 2.1 Module Map

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

### 2.2 Dependency Flow (Current)

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

### 2.3 Key Observations

1. **Jido is already deeply integrated** — 13+ modules directly use Jido behaviours (`Jido.Action`, `Jido.Plugin`, `Jido.Storage`, `Jido.AI.Agent`, `ReAct.RequestTransformer`). This is a feature, not a problem. Our packages should preserve this direct relationship.

2. **WorkspaceLive has excessive coupling** — it directly accesses agent internals (`Jido.AgentServer.state(pid)`), storage adapters, and manages agent lifecycle. The fix is not to hide Jido behind a facade, but to provide **convenience functions** that make common operations easy while still allowing direct Jido access when needed.

3. **The orchestration layer (Runner, PendingQueue, MessageInjector, etc.) is app-agnostic** — nothing in these modules is specific to Murmur's domain. They implement general multi-agent patterns using standard Jido APIs.

4. **Plugins are already Jido-native** — StreamingPlugin and ArtifactPlugin implement `Jido.Plugin` directly. This is exactly right. Extraction should preserve this — consumers add them to their `Jido.AI.Agent` plugin list directly.

5. **Storage adapter is already Jido-native** — `Murmur.Storage.Ecto` implements `Jido.Storage` directly. Consumers configure it in their `use Jido` call. No wrapper needed.

6. **Tools are already Jido-native** — TellAction, AddTask, ArxivSearch all implement `Jido.Action` directly. Consumers add them to their `Jido.AI.Agent` tools list. No wrapper needed.

7. **Workspace/Session management is semi-generic** — the concept of "workspaces containing agent sessions" is reusable, but the max-8-agents constraint and specific field names are domain choices.

8. **Task management tools are reusable** — AddTask/UpdateTask/ListTasks implement a Kanban-style task board that any multi-agent app could use.

9. **ArxivSearch/DisplayPaper are domain-specific but reusable** — they're self-contained `Jido.Action` tools that could be a plugin package.

### 2.4 Jido Integration Audit

This audit maps exactly where Jido types appear in the codebase, confirming that Jido is the foundation — not an implementation detail to hide:

| Module | Jido Interface Used | Jido Types in API | Status |
|---|---|---|---|
| `GeneralAgent` | `use Jido.AI.Agent` | Agent config DSL | ✅ Native — keep as-is |
| `ArxivAgent` | `use Jido.AI.Agent` | Agent config DSL | ✅ Native — keep as-is |
| `StreamingPlugin` | `use Jido.Plugin` | `Jido.Signal` in handler | ✅ Native — keep as-is |
| `ArtifactPlugin` | `use Jido.Plugin` | `Jido.Signal` in handler | ✅ Native — keep as-is |
| `TellAction` | `use Jido.Action` | `Jido.Signal.ID`, action context | ✅ Native — keep as-is |
| `AddTask/UpdateTask/ListTasks` | `use Jido.Action` | `Jido.Signal.ID`, action context | ✅ Native — keep as-is |
| `ArxivSearch` | `use Jido.Action` | `Jido.Agent.Directive.Emit` | ✅ Native — keep as-is |
| `StoreArtifact` | `use Jido.Action` | Action context `ctx[:state]` | ✅ Native — keep as-is |
| `MessageInjector` | `@behaviour ReAct.RequestTransformer` | Request/context types | ✅ Native — keep as-is |
| `Storage.Ecto` | `@behaviour Jido.Storage` | `Jido.Thread`, `Jido.Thread.Entry` | ✅ Native — keep as-is |
| `Murmur.Jido` | `use Jido` | Agent lifecycle API | ✅ Native — consumer defines their own |
| `Runner` | Calls Jido via adapter | Agent pids, ask/await | ✅ Native — uses Jido internals correctly |
| `WorkspaceLive` | Direct `Jido.AgentServer.state()` | Thread entries, agent state | ⚠️ Needs convenience layer (not abstraction wall) |

**Conclusion:** The codebase is already Jido-native. The extraction should preserve every one of these Jido integration points, not wrap them.

---

## 3. Proposed Package Architecture

### 3.1 Package Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Consumer Application                          │
│  (e.g., murmur, project-x, project-y)                          │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ App Agents   │  │ App Frontend │  │ App Business Logic   │  │
│  │ (use         │  │ (LiveViews,  │  │ (custom contexts,    │  │
│  │  Jido.AI.    │  │  templates)  │  │  schemas, etc.)      │  │
│  │  Agent)      │  │              │  │                      │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────────────────┘  │
│         │                  │                                     │
│         │  ┌───────────────┴─────────────────────────────┐      │
│         │  │  jido_workbench (reusable Jido components)  │      │
│         │  │  Pre-built Jido.Plugin modules               │      │
│         │  │  Pre-built Jido.Action modules               │      │
│         │  │  Jido.Storage Ecto adapter                   │      │
│         │  │  ReAct.RequestTransformer (MessageInjector)  │      │
│         │  │  Orchestration (Runner, PendingQueue)        │      │
│         │  │  Workspace/Session Ecto schemas              │      │
│         │  │  LiveView components                         │      │
│         │  └───────────────┬─────────────────────────────┘      │
│         │                  │                                     │
│         │  ┌───────────────┴─────────────────────────────┐      │
│         │  │   Optional Plugin Packages                   │      │
│         │  │   (also provide Jido.Action tools directly)  │      │
│         │  │   jido_tasks_plugin · jido_arxiv_plugin      │      │
│         │  └───────────────┬─────────────────────────────┘      │
│         │                  │                                     │
│  ┌──────┴──────────────────┴─────────────────────────────────┐  │
│  │              jido ecosystem (foundation)                    │  │
│  │  jido · jido_ai · jido_signal · jido_action · req_llm     │  │
│  │                                                             │  │
│  │  Consumer projects use Jido DIRECTLY — our packages        │  │
│  │  sit alongside, not on top.                                │  │
│  └─────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

**Key difference from a naïve extraction:** The consumer application has arrows going **directly to Jido** as well as to the workbench. The workbench does not sit between the consumer and Jido — it sits beside it.

### 3.2 Package Definitions

#### Package 1: `jido_workbench` (Reusable Jido Multi-Agent Components)

**Purpose:** A collection of pre-built Jido components for building multi-agent workspace applications. Does NOT wrap or replace Jido APIs.

**What it provides (all Jido-native):**

| Component | Jido Interface | What Consumer Does |
|---|---|---|
| `StreamingPlugin` | `Jido.Plugin` | Adds to agent's `plugins:` list |
| `ArtifactPlugin` | `Jido.Plugin` | Adds to agent's `plugins:` list |
| `TellAction` | `Jido.Action` | Adds to agent's `tools:` list |
| `StoreArtifact` | `Jido.Action` | Used internally by ArtifactPlugin |
| `MessageInjector` | `ReAct.RequestTransformer` | Sets as agent's `request_transformer:` |
| `Storage.Ecto` | `Jido.Storage` | Configures in `use Jido, storage: {...}` |
| Runner, PendingQueue | Uses Jido APIs internally | Consumer calls `Runner.send_message/2` |
| Workspace, AgentSession | Ecto schemas | Consumer uses for data management |
| LiveView components | Phoenix.Component | Consumer includes in templates |

**What consumers still do directly with Jido:**
- `use Jido.AI.Agent` to define agents (with our plugins/tools in the lists)
- `use Jido, otp_app: :my_app, storage: {JidoWorkbench.Storage.Ecto, []}` to bootstrap
- Call `Jido.AgentServer.state(pid)` when they need direct agent state access
- Write custom `Jido.Plugin` modules alongside ours
- Write custom `Jido.Action` tools alongside ours
- Implement `Jido.Storage` for non-Ecto backends if needed

**Dependencies:**
- `jido`, `jido_ai`, `jido_signal`, `jido_action`, `req_llm`
- `phoenix`, `phoenix_live_view`, `phoenix_ecto`, `ecto_sql`, `postgrex`
- `phoenix_pubsub`, `jason`

---

#### Package 2: `jido_tasks_plugin` (Task Management — Jido.Action Tools)

**Purpose:** Kanban-style task board for multi-agent collaboration. Ships as `Jido.Action` modules that consumers add to their agents.

**Contains:**
- `JidoTasksPlugin.Tools.AddTask` — `Jido.Action` implementation
- `JidoTasksPlugin.Tools.UpdateTask` — `Jido.Action` implementation
- `JidoTasksPlugin.Tools.ListTasks` — `Jido.Action` implementation
- `JidoTasksPlugin.Task` — Ecto schema
- `JidoTasksPlugin.Tasks` — Context (CRUD, filtering, stats)
- `JidoTasksPlugin.Components.TaskBoard` — LiveView component
- Migration templates

**How consumers use it (Jido-native composition):**
```elixir
# Consumer agent — tools from the plugin go directly into Jido.AI.Agent tools list
defmodule MyApp.Agents.ProjectManager do
  use Jido.AI.Agent,
    name: "project_manager",
    tools: [
      JidoTasksPlugin.Tools.AddTask,      # ← From plugin
      JidoTasksPlugin.Tools.UpdateTask,    # ← From plugin
      JidoTasksPlugin.Tools.ListTasks,     # ← From plugin
      JidoWorkbench.TellAction,            # ← From workbench
      MyApp.Tools.CustomTool               # ← Consumer's own Jido.Action
    ],
    plugins: [
      JidoWorkbench.StreamingPlugin,       # ← From workbench
      JidoWorkbench.ArtifactPlugin         # ← From workbench
    ],
    request_transformer: JidoWorkbench.MessageInjector,
    model: :fast,
    system_prompt: "You are a project manager..."
end
```

Note: The consumer's agent definition is pure Jido. Plugin tools are just `Jido.Action` modules — they compose seamlessly with consumer-written tools and workbench tools.

**Dependencies:**
- `jido_workbench`, `jido_action`, `ecto_sql`

---

#### Package 3: `jido_arxiv_plugin` (Academic Research — Jido.Action Tools)

**Purpose:** arXiv paper search and display for research-oriented agents. Ships as `Jido.Action` modules.

**Contains:**
- `JidoArxivPlugin.Tools.ArxivSearch` — `Jido.Action` that emits `Jido.Agent.Directive.Emit` for artifact signals
- `JidoArxivPlugin.Tools.DisplayPaper` — `Jido.Action` implementation
- `JidoArxivPlugin.Components.PaperList` — LiveView component
- `JidoArxivPlugin.Components.PdfViewer` — LiveView component

**Dependencies:**
- `jido_workbench` (for `JidoWorkbench.Artifact` emit helper), `jido_action`, `req`, `sweet_xml`

**Note:** The ArxivSearch tool uses `JidoWorkbench.Artifact.emit/4` which returns a `Jido.Agent.Directive.Emit` — this is a standard Jido directive. The workbench helper simply makes it convenient to construct the signal; consumers could construct the directive manually using Jido APIs if they preferred.

---

#### Future Plugin Packages (examples):
- `jido_web_search_plugin` — Web search tool
- `jido_code_plugin` — Code execution/analysis tools
- `jido_calendar_plugin` — Calendar/scheduling tools
- `jido_email_plugin` — Email drafting/sending tools

---

## 4. Detailed Extraction Plan: `jido_workbench`

### 4.1 Module Mapping

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

### 4.2 Design Decisions: Jido-Native Abstractions

The abstractions we introduce must **extend** Jido, not replace it. Here's what we introduce and — critically — what we do NOT introduce.

#### 4.2.1 Configuration Module (Required — app-specific references)

The package needs to access the consuming application's Repo, Jido module, and PubSub without hardcoding. This is the one non-Jido abstraction that's genuinely necessary:

```elixir
defmodule JidoWorkbench do
  @moduledoc """
  Configuration for JidoWorkbench.

  This module provides access to application-specific modules (Repo, PubSub, etc.)
  that the workbench needs to interact with. It does NOT wrap or replace any Jido APIs.
  """

  def repo, do: Application.fetch_env!(:jido_workbench, :repo)
  def jido, do: Application.fetch_env!(:jido_workbench, :jido)
  def pubsub, do: Application.fetch_env!(:jido_workbench, :pubsub)
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

#### 4.2.2 Catalog — Profile Registry (Config-Driven, Not a New Behaviour)

Currently profiles (GeneralAgent, ArxivAgent) are hardcoded in the Catalog. We make it configuration-driven. 

**We do NOT create a `JidoWorkbench.AgentProfile` behaviour.** Agent profiles are already defined using `use Jido.AI.Agent` — we should not create a parallel behaviour. Instead, we require that profile modules implement a single function `catalog_meta/0` which is already the pattern used in the codebase:

```elixir
# This is all the "contract" we need — a convention, not a behaviour
# The module is already a Jido.AI.Agent, which defines name/0 and description/0
# We just need catalog_meta/0 for UI metadata (color, icon, etc.)
defmodule MyApp.Agents.CustomerSupport do
  use Jido.AI.Agent,
    name: "customer_support",
    description: "Handles customer inquiries",
    model: :fast,
    tools: [JidoWorkbench.TellAction, JidoTasksPlugin.Tools.AddTask],
    plugins: [JidoWorkbench.StreamingPlugin, JidoWorkbench.ArtifactPlugin],
    request_transformer: JidoWorkbench.MessageInjector,
    system_prompt: "You are a customer support agent..."

  # Only addition for workbench catalog — not a separate behaviour
  def catalog_meta, do: %{color: "blue"}
end
```

Catalog reads profiles from config:
```elixir
config :jido_workbench,
  profiles: [
    MyApp.Agents.CustomerSupport,
    MyApp.Agents.BillingAgent
  ]
```

**Why not a behaviour?** Because `Jido.AI.Agent` already IS the behaviour. Adding `JidoWorkbench.AgentProfile` would create a redundant parallel contract. The `catalog_meta/0` convention is lightweight and doesn't require consumers to add another `@behaviour` declaration — they just implement a function.

#### 4.2.3 Workspace Convenience Functions (NOT a Facade That Hides Jido)

The current WorkspaceLive directly calls `Jido.AgentServer.state(pid)`, `Murmur.Jido.start_agent()`, etc. The previous version of this plan proposed a "WorkspaceFacade" that would hide all Jido access. **That was wrong.**

Instead, we provide **convenience functions** that make common operations easy while leaving Jido fully accessible:

```elixir
defmodule JidoWorkbench.AgentHelper do
  @moduledoc """
  Convenience functions for common agent operations in workspace contexts.

  These functions use Jido APIs internally and return Jido types.
  Consumers can always bypass these and call Jido directly.
  """

  @doc """
  Start or restore an agent for a session.
  Returns the Jido agent pid — consumers can use this pid
  with any Jido.AgentServer function directly.
  """
  @spec ensure_agent_started(AgentSession.t()) :: {:ok, pid()} | {:error, term()}
  def ensure_agent_started(session)

  @doc """
  Load messages for a session, projected through UITurn.
  Returns Jido Thread entries projected into display format.
  For raw Jido.Thread access, call Jido.AgentServer.state(pid) directly.
  """
  @spec load_messages(AgentSession.t()) :: [map()]
  def load_messages(session)

  @doc """
  Load artifacts for a session from the agent's Jido state.
  For direct state access, use Jido.AgentServer.state(pid).
  """
  @spec load_artifacts(AgentSession.t()) :: %{String.t() => term()}
  def load_artifacts(session)

  @doc """
  Subscribe to all relevant PubSub topics for a session.
  Signals are broadcast as Jido.Signal structs — consumers handle them
  using standard Jido signal pattern matching.
  """
  @spec subscribe(workspace_id :: String.t(), session_id :: String.t()) :: :ok
  def subscribe(workspace_id, session_id)

  @doc """
  Clean up Jido storage (checkpoints + threads) for all agents in a workspace.
  Uses the Jido.Storage adapter configured in the consumer's `use Jido` call.
  """
  @spec cleanup_workspace_storage(workspace_id :: String.t()) :: :ok
  def cleanup_workspace_storage(workspace_id)
end
```

**Critical difference from the old "WorkspaceFacade":**
- Returns Jido types (pids, signals, thread entries) — doesn't wrap them
- Documents that consumers CAN call Jido directly for advanced use cases
- Named `AgentHelper` (helper, not facade) to signal it's a convenience layer
- Consumer LiveViews can use BOTH the helpers AND direct Jido calls

**Example — consumer LiveView using both helper and direct Jido:**
```elixir
def mount(%{"id" => workspace_id}, _session, socket) do
  # Use workbench helper for common setup
  {:ok, pid} = JidoWorkbench.AgentHelper.ensure_agent_started(session)
  messages = JidoWorkbench.AgentHelper.load_messages(session)

  # BUT consumer can also call Jido directly for advanced features
  {:ok, %{agent: agent}} = Jido.AgentServer.state(pid)
  custom_data = agent.state.my_custom_field  # Direct Jido state access

  {:ok, assign(socket, messages: messages, custom_data: custom_data)}
end
```

#### 4.2.4 Artifact Renderer Registry (Config, Not Behaviour)

Currently artifact rendering is hardcoded. We make it configurable, but keep it simple — a config map, not a new behaviour:

```elixir
config :jido_workbench,
  artifact_renderers: %{
    "papers" => JidoArxivPlugin.Components.PaperList,
    "displayed_paper" => JidoArxivPlugin.Components.PdfViewer,
    "tasks" => JidoTasksPlugin.Components.TaskBoard
  }
```

Renderer modules just need to export `badge/1` and `detail/1` function components. This is a **convention**, not a behaviour — no `@behaviour` declaration needed. If a renderer isn't found, the generic renderer is used.

#### 4.2.5 What We Do NOT Create (Jido Interplay Preservation)

| Rejected Abstraction | Why | What to Do Instead |
|---|---|---|
| `JidoWorkbench.AgentProfile` behaviour | Duplicates `Jido.AI.Agent` | Convention: `catalog_meta/0` function |
| `JidoWorkbench.Plugin` behaviour for plugin packages | Duplicates `Jido.Plugin` | Plugins just implement `Jido.Plugin` |
| `JidoWorkbench.Action` behaviour for tools | Duplicates `Jido.Action` | Tools just implement `Jido.Action` |
| `JidoWorkbench.Storage` wrapper | Duplicates `Jido.Storage` | Storage implements `Jido.Storage` directly |
| `JidoWorkbench.RequestTransformer` wrapper | Duplicates `ReAct.RequestTransformer` | Implement Jido's behaviour directly |
| `JidoWorkbench.Signal` wrapper types | Duplicates `Jido.Signal` | Use `Jido.Signal` everywhere |
| WorkspaceFacade that hides pids | Prevents direct Jido access | AgentHelper that returns Jido types |

### 4.3 Migration Strategy

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

### 4.4 PubSub Topic Contracts

These are the stable PubSub contracts. Note that streaming signals carry **native `Jido.Signal` structs** — consumers handle them using standard Jido signal pattern matching:

| Topic Pattern | Message | Source | Jido Types |
|---|---|---|---|
| `"workspace:#{workspace_id}"` | `{:new_message, session_id, msg}` | Runner, TellAction | `msg.id` is `Jido.Signal.ID` |
| `"agent_stream:#{session_id}"` | `{:agent_signal, session_id, signal}` | StreamingPlugin | `signal` is `Jido.Signal` struct |
| `"agent_artifacts:#{session_id}"` | `{:artifact_update, session_id, name, data, mode}` | ArtifactPlugin | Originated from `Jido.Agent.Directive.Emit` |
| `"tasks:#{workspace_id}"` | `{:task_created, task}`, `{:task_updated, task}` | Tasks context | N/A (Ecto struct) |

**Jido interplay note:** The `{:agent_signal, session_id, signal}` broadcasts carry the full `Jido.Signal` struct. Consumers can pattern-match on signal type, inspect data, and use any Jido signal processing they want. We do NOT strip the signal into a simpler format.

### 4.5 Supervision Tree

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

## 5. Detailed Extraction Plan: Plugin Packages

### 5.1 `jido_tasks_plugin`

```
jido_tasks_plugin/
├── lib/
│   ├── jido_tasks_plugin.ex              # Module docs + version
│   ├── jido_tasks_plugin/
│   │   ├── task.ex                       # Ecto schema
│   │   ├── tasks.ex                      # Context (CRUD)
│   │   ├── tools/
│   │   │   ├── add_task.ex              # use Jido.Action (Jido-native)
│   │   │   ├── update_task.ex           # use Jido.Action (Jido-native)
│   │   │   └── list_tasks.ex            # use Jido.Action (Jido-native)
│   │   └── components/
│   │       └── task_board.ex            # LiveView component
├── priv/
│   └── templates/
│       └── create_tasks_migration.exs   # Migration template
└── mix.exs
```

**Jido interplay:** All tools implement `Jido.Action` directly. Consumers add them to their `Jido.AI.Agent` tools list — exactly the same way they add any other Jido action. The plugin doesn't introduce any new behaviours or abstractions.

### 5.2 `jido_arxiv_plugin`

```
jido_arxiv_plugin/
├── lib/
│   ├── jido_arxiv_plugin.ex
│   ├── jido_arxiv_plugin/
│   │   ├── tools/
│   │   │   ├── arxiv_search.ex          # use Jido.Action (emits Jido.Agent.Directive.Emit)
│   │   │   └── display_paper.ex         # use Jido.Action
│   │   └── components/
│   │       ├── paper_list.ex            # LiveView component
│   │       └── pdf_viewer.ex            # LiveView component
└── mix.exs
```

### 5.3 Plugin Package Design Rules (Jido-Native)

Plugin packages follow these rules to ensure seamless Jido interplay:

1. **Tools implement `Jido.Action` directly** — no wrapper behaviours
2. **Plugins implement `Jido.Plugin` directly** — if the package includes signal handlers
3. **Artifact emission uses `Jido.Agent.Directive.Emit`** — the standard Jido directive system
4. **Action context uses Jido's context map** — `context[:workspace_id]`, `context[:sender_name]`, etc.
5. **Signal IDs use `Jido.Signal.ID`** — not a wrapper type
6. **No `JidoWorkbench.Plugin` meta-behaviour** — plugins are just collections of Jido components

**Rationale:** When a consumer reads plugin source code, they should see standard Jido patterns they already know. A consumer who has learned Jido should be immediately productive with any plugin package.

### 5.4 How Consumers Compose Agents from Plugins

The key insight: **agent composition is just Jido.AI.Agent configuration**. No special plugin registration system needed.

```elixir
defmodule MyApp.Agents.ResearchAssistant do
  use Jido.AI.Agent,
    name: "research_assistant",
    description: "Searches papers and manages tasks",
    model: :capable,
    tools: [
      # From jido_workbench
      JidoWorkbench.TellAction,

      # From jido_tasks_plugin
      JidoTasksPlugin.Tools.AddTask,
      JidoTasksPlugin.Tools.UpdateTask,
      JidoTasksPlugin.Tools.ListTasks,

      # From jido_arxiv_plugin
      JidoArxivPlugin.Tools.ArxivSearch,
      JidoArxivPlugin.Tools.DisplayPaper,

      # Consumer's own custom tools (also Jido.Action)
      MyApp.Tools.SummarizeDocument
    ],
    plugins: [
      # From jido_workbench
      JidoWorkbench.StreamingPlugin,
      JidoWorkbench.ArtifactPlugin,

      # Consumer's own custom plugins (also Jido.Plugin)
      MyApp.Plugins.AuditLogPlugin
    ],
    request_transformer: JidoWorkbench.MessageInjector,
    system_prompt: "You are a research assistant..."

  def catalog_meta, do: %{color: "violet"}
end
```

This is pure Jido composition. The consumer doesn't need to learn any workbench-specific APIs for agent definition — just standard `Jido.AI.Agent`.

---

## 6. Architectural Boundaries & Stable Contracts

### 6.1 Contract Hierarchy (Jido-First)

```
Level 0: Jido Ecosystem — THE PRIMARY API
  ├── Jido.Storage behaviour           ← consumers implement directly
  ├── Jido.Action behaviour (run/2)    ← tools implement directly
  ├── Jido.Plugin behaviour             ← plugins implement directly
  ├── Jido.AI.Agent macro               ← agents use directly
  ├── Jido.Signal struct                ← used throughout, never wrapped
  ├── Jido.Thread / Jido.Thread.Entry   ← used throughout, never wrapped
  ├── Jido.Agent.Directive.Emit         ← used for side effects, never wrapped
  └── ReAct.RequestTransformer behaviour ← transformers implement directly

Level 1: JidoWorkbench — REUSABLE JIDO COMPONENTS
  ├── Pre-built Jido.Plugin modules (StreamingPlugin, ArtifactPlugin)
  ├── Pre-built Jido.Action modules (TellAction, StoreArtifact)
  ├── Pre-built Jido.Storage adapter (Storage.Ecto)
  ├── Pre-built ReAct.RequestTransformer (MessageInjector)
  ├── Orchestration helpers (Runner, PendingQueue, TeamInstructions)
  ├── Convenience functions (AgentHelper — returns Jido types)
  ├── Ecto schemas (Workspace, AgentSession)
  ├── Configuration contract (repo, jido, pubsub, profiles)
  ├── PubSub topic/message contracts (carry Jido.Signal structs)
  └── LiveView components

Level 2: Plugin Packages — ADDITIONAL JIDO COMPONENTS
  ├── Additional Jido.Action tools (AddTask, ArxivSearch, etc.)
  ├── Additional LiveView components
  ├── Ecto schemas and migration templates
  └── Nothing plugin-specific that wraps Jido

Level 3: Consumer Application
  ├── use Jido.AI.Agent (DIRECT — not through workbench)
  ├── use Jido, storage: {JidoWorkbench.Storage.Ecto, []} (DIRECT)
  ├── Compose tools/plugins from all levels
  ├── Write custom Jido.Action / Jido.Plugin modules
  ├── Call Jido APIs directly alongside workbench helpers
  └── Build custom LiveViews
```

**Key insight:** Levels 1 and 2 provide **implementations** of Level 0 interfaces. Level 3 **uses** Level 0 directly and picks implementations from Levels 1 and 2. There is no separate "workbench API" layer between the consumer and Jido.

### 6.2 Versioning Strategy

**Semantic Versioning with these rules:**

- **Patch (0.x.Y):** Bug fixes, performance improvements, no API changes
- **Minor (0.X.0):** New features, new optional configuration, backward-compatible changes
- **Major (X.0.0):** Breaking changes to workbench-specific contracts (below)

**Workbench-specific contracts that require major version bumps to break:**

1. Configuration keys and expected value shapes (`config :jido_workbench, ...`)
2. PubSub topic patterns and message tuple shapes
3. `JidoWorkbench.AgentHelper` public function signatures
4. Database table schemas (migrations should always be additive)
5. `catalog_meta/0` convention expectations

**Contracts that are NOT ours to version** (they follow Jido's versioning):

1. `Jido.Action` run/2 callback signature — that's Jido's contract
2. `Jido.Plugin` handle_signal/2 callback signature — that's Jido's contract
3. `Jido.Storage` behaviour callbacks — that's Jido's contract
4. `Jido.Signal` struct shape — that's Jido's contract
5. `Jido.AI.Agent` configuration DSL — that's Jido's contract

This is a **major advantage** of the Jido-native approach: we have far fewer contracts to maintain because we delegate to Jido's well-maintained interfaces.

### 6.3 Boundary Rules (Jido-Permissive)

```
Consumer App
  ├── CAN depend on: Jido (DIRECT), JidoWorkbench components, Plugin tools
  ├── CAN call Jido APIs directly (AgentServer, Signal, Thread, etc.)
  ├── CAN write custom Jido.Action / Jido.Plugin alongside workbench ones
  ├── CAN access agent state via Jido.AgentServer.state(pid)
  │
JidoWorkbench
  ├── CAN depend on: Jido ecosystem, Phoenix, Ecto
  ├── MUST use Jido types in public API (Signal, Thread, pids)
  ├── MUST NOT wrap or hide Jido types behind workbench-specific types
  ├── CANNOT depend on: Consumer app modules (use config for repo/jido/pubsub)
  │
Plugin Packages
  ├── CAN depend on: JidoWorkbench, Jido ecosystem
  ├── MUST implement Jido behaviours directly (Action, Plugin)
  ├── MUST NOT create wrapper behaviours
  ├── CANNOT depend on: Consumer app modules, other plugins
```

---

## 7. Refactoring Execution Plan

### Phase 1: Introduce Convenience Layer In-Place (1-2 weeks)

**Goal:** Create the convenience functions and configuration hooks within the existing Murmur codebase before extracting anything. This de-risks the extraction without adding abstraction walls.

1. **Create AgentHelper module**
   - Extract common agent operations from `WorkspaceLive` into `Murmur.Agents.AgentHelper`
   - Functions: `ensure_agent_started/1`, `load_messages/1`, `load_artifacts/1`, `subscribe/2`, `cleanup_workspace_storage/1`
   - These functions use Jido APIs internally and **return Jido types** (pids, thread entries, etc.)
   - Update `WorkspaceLive` to use helpers for common operations
   - **Important:** WorkspaceLive can still call Jido directly for anything the helper doesn't cover
   - **Test:** All existing LiveView tests pass without changes

2. **Make Catalog configuration-driven**
   - Move profile list from hardcoded to application config
   - Existing agents already implement `catalog_meta/0` — no behaviour change needed
   - **Test:** Catalog tests pass with configuration-driven profiles

3. **Make artifact rendering configurable**
   - Replace hardcoded dispatch with config-driven registry
   - **Test:** Artifact rendering tests pass

4. **Parameterize app-specific references**
   - Replace all `Murmur.Repo` references with configurable module
   - Replace all `Murmur.Jido` references with configurable module
   - Replace all `Murmur.PubSub` references with configurable module
   - **Test:** All tests pass with the same modules configured via application env

### Phase 2: Extract `jido_workbench` (1-2 weeks)

**Goal:** Move the convenience modules into a separate Hex package. The package provides reusable Jido components, not a wrapper layer.

1. **Create package skeleton**
   ```
   jido_workbench/
   ├── lib/jido_workbench.ex          # Config access (repo, jido, pubsub)
   ├── lib/jido_workbench/
   │   ├── agent_helper.ex            # Convenience functions (returns Jido types)
   │   ├── runner.ex                  # Orchestration (uses Jido APIs)
   │   ├── pending_queue.ex           # ETS queue
   │   ├── table_owner.ex             # ETS lifecycle
   │   ├── message_injector.ex        # ReAct.RequestTransformer impl
   │   ├── team_instructions.ex       # Collaboration prompt builder
   │   ├── streaming_plugin.ex        # Jido.Plugin impl
   │   ├── artifact_plugin.ex         # Jido.Plugin impl
   │   ├── artifact.ex                # Signal helper (returns Jido.Agent.Directive.Emit)
   │   ├── tell_action.ex             # Jido.Action impl
   │   ├── catalog.ex                 # Profile registry (config-driven)
   │   ├── ui_turn.ex                 # Thread → display projection
   │   ├── llm.ex                     # LLM adapter behaviour
   │   ├── llm/real.ex                # Production adapter
   │   ├── actions/store_artifact.ex  # Jido.Action impl
   │   ├── storage/                   # Jido.Storage impl
   │   │   ├── ecto.ex
   │   │   ├── checkpoint.ex
   │   │   └── thread_entry.ex
   │   ├── workspaces/                # Ecto schemas
   │   │   ├── workspace.ex
   │   │   └── agent_session.ex
   │   ├── workspaces.ex              # Context
   │   └── supervisor.ex              # OTP supervisor
   ├── mix.exs
   ├── test/
   └── priv/templates/                # Migration templates
   ```

2. **Move modules** (following the mapping in Section 4.1)
   - All Jido.Plugin/Action/Storage implementations keep their `use Jido.*` macros
   - No wrapper behaviours are introduced
   - All public functions return Jido types where applicable

3. **Create migration generator**
   - `mix jido_workbench.install` task
   - Generates migration files into consumer's `priv/repo/migrations/`

4. **Create test helpers**
   - `JidoWorkbench.TestCase` — equivalent of current `AgentCase`
   - Mock LLM helpers (wrapping Mox stubs for `Jido.AI.Agent` ask/await)
   - Helpers use Jido types — consumers test with Jido's own test patterns

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

## 8. Risks & Mitigations

### 8.1 Jido Version Coupling

**Risk:** Since we expose Jido types directly (not wrapped), a breaking change in Jido breaks our consumers too.

**Mitigation:** This is actually a feature — consumers are already Jido projects. When Jido releases a major version, consumers need to upgrade regardless. Our packages declare compatible Jido version ranges in `mix.exs` and we test against Jido's main branch in CI. We upgrade in lockstep because we're part of the Jido ecosystem, not a separate layer.

### 8.2 Circular Dependencies

**Risk:** `TellAction` depends on `Workspaces` context, which depends on `Repo`. If `Repo` is in the consumer app, `TellAction` can't call it directly.

**Mitigation:** All database access goes through the configurable `repo()` function in `JidoWorkbench`. The consumer configures their Repo module at startup.

### 8.3 ETS Table Naming Conflicts

**Risk:** Multiple consumer apps running in the same BEAM node could conflict on ETS table names.

**Mitigation:** Namespace ETS tables with the OTP app name: `:jido_workbench_pending_messages` or use `{:via, Registry, {JidoWorkbench.Registry, :pending_messages}}`.

### 8.4 PubSub Name Conflicts

**Risk:** Hardcoded PubSub name won't work in multi-app deployments.

**Mitigation:** Already addressed — PubSub module is configurable via application env.

### 8.5 Migration Ordering

**Risk:** Plugin migrations depend on workbench migrations (e.g., tasks table references workspaces table).

**Mitigation:** Migration generator enforces ordering via timestamps. Document dependency chain in installation instructions.

### 8.6 LiveView Component Styling

**Risk:** Tailwind classes from the package may not be picked up by the consumer's CSS build.

**Mitigation:** Document the required `@source` directive in the consumer's `app.css`:
```css
@source "../../deps/jido_workbench";
@source "../../deps/jido_tasks_plugin";
```

### 8.7 Breaking Changes During Early Development

**Risk:** The API will inevitably change as we learn from the first few consumer apps.

**Mitigation:**
- Start at version `0.x.y` to signal instability
- Use `@deprecated` annotations before removing features
- Maintain a CHANGELOG with migration guides
- Consider a `JidoWorkbench.Compat` module for backward compatibility shims

---

## 9. Open Questions for Discussion

1. **Package naming:** Is `jido_workbench` the right name? Alternatives: `jido_workspace`, `jido_multi_agent`, `jido_collab`, `jido_studio`. Given the Jido-native philosophy, the `jido_` prefix signals that this is part of the Jido ecosystem.

2. **Monorepo vs multi-repo:** Should `jido_workbench` and plugins live in the same GitHub repo (monorepo with `mix.exs` in subdirectories) or separate repos? Monorepo is easier for coordinated changes; multi-repo is better for independent versioning.

3. **LiveView components: opt-in or required?** Should the workbench ship with "batteries included" LiveView components, or should it be purely a backend package with consumers building their own UI?

4. **Workspace schema flexibility:** Should the workspace/session schemas be extensible (e.g., allow consumers to add custom fields)? Or should consumers wrap them with their own schemas that reference workbench schemas?

5. **Max agents per workspace:** Currently hardcoded to 8. Should this be configurable? Should it be enforced at the package level or left to consumers?

6. **Authentication/authorization:** The current codebase has no auth. Should the workbench include hooks for authorization (e.g., "can this user access this workspace?") or leave it entirely to consumers?

7. **Multi-tenancy:** Some consumer apps may need multi-tenant workspaces. Should the workbench account for this in its schema design (e.g., optional `tenant_id` on workspaces)?

8. **Jido version pinning:** Should `jido_workbench` pin to a specific Jido minor version, or use a loose `~> 2.0` requirement? Tight pinning is safer but creates dep resolution headaches. Loose pinning relies on Jido maintaining backward compatibility.

9. **Custom RequestTransformers:** Should the workbench support composing multiple `ReAct.RequestTransformer` implementations? Currently only one can be set per agent. If a consumer wants their own transformer alongside MessageInjector, how should that work? This may require upstream Jido changes.

---

## 10. Summary of Deliverables

| Deliverable | Type | Jido Relationship | Priority |
|---|---|---|---|
| `jido_workbench` Hex package | Core package | Provides pre-built Jido components | P0 — Must have |
| AgentHelper convenience functions | Helpers | Returns Jido types (pids, signals) | P0 — Must have |
| Config-driven Catalog | Configuration | Discovers `Jido.AI.Agent` modules | P0 — Must have |
| Config-driven artifact renderers | Configuration | N/A (pure UI) | P0 — Must have |
| Migration generators | Tooling | Includes Jido storage tables | P0 — Must have |
| Reusable LiveView components | UI library | Renders Jido.Signal streams | P1 — Should have |
| `jido_tasks_plugin` | Plugin package | Ships `Jido.Action` tools | P1 — Should have |
| `jido_arxiv_plugin` | Plugin package | Ships `Jido.Action` tools | P2 — Nice to have |
| Test helpers | DX | Wraps Mox stubs for Jido APIs | P1 — Should have |
| Getting Started guide | Documentation | Shows Jido-native composition | P0 — Must have |
| Second consumer validation | Validation | Confirms Jido interplay works | P1 — Should have |

---

## Appendix A: Current Coupling Map (Jido Integration Highlighted)

This diagram shows every module-to-module dependency in the current codebase, color-coded by extraction target. Note how Jido is present throughout — this is by design.

```
🟦 = jido_workbench extraction target
🟩 = jido_tasks_plugin extraction target
🟪 = jido_arxiv_plugin extraction target
⬜ = stays in consumer app (Murmur)
🔵 = direct Jido API usage (PRESERVED, not hidden)

⬜ MurmurWeb.WorkspaceLive
  → 🟦 Runner (send_message)
  → 🟦 Catalog (list_profiles, get_profile!, agent_color)
  → 🟦 StreamingPlugin (stream_topic)
  → 🟦 Artifact (artifact_topic)
  → 🟦 UITurn (project_entries)
  → 🟦 Workspaces (CRUD)
  → 🟩 Tasks (CRUD)
  → 🔵 Jido.AgentServer.state(pid) — ALLOWED (direct Jido access)
  → 🔵 MyApp.Jido.start_agent/stop_agent/whereis/thaw — ALLOWED (consumer's Jido module)
  → 🔵 Jido.Signal.ID — ALLOWED (Jido type used directly)
  NOTE: With AgentHelper, common operations get convenience functions,
        but direct Jido access remains available for advanced use.

🟦 Runner
  → 🟦 Catalog (agent_module)
  → 🟦 PendingQueue (enqueue, drain, pending?)
  → 🔵 MyApp.Jido (whereis, hibernate) — uses Jido via consumer's module
  → 🟦 LLM (ask, await)

🟦 TellAction (implements Jido.Action directly)
  → 🟦 Runner (send_message)
  → 🟦 Workspaces (find_agent_session_by_name)
  → 🔵 Jido.Signal.ID (generates message IDs)

🟦 MessageInjector (implements Jido.AI.Reasoning.ReAct.RequestTransformer directly)
  → 🟦 PendingQueue (drain)
  → 🟦 TeamInstructions (build)

🟦 TeamInstructions
  → 🟦 Workspaces (list_agent_sessions)
  → 🟦 Catalog (get_profile!)

🟦 StreamingPlugin (implements Jido.Plugin directly)
  → 🔵 Broadcasts Jido.Signal structs via PubSub

🟦 ArtifactPlugin (implements Jido.Plugin directly)
  → 🔵 Receives Jido.Signal, returns Jido override directive

🟦 Storage.Ecto (implements Jido.Storage directly)
  → 🔵 Returns Jido.Thread and Jido.Thread.Entry types

🟩 AddTask / UpdateTask / ListTasks (implement Jido.Action directly)
  → 🟩 Tasks (create_task, update_task, list_tasks)
  → 🟦 Runner (send_message) [for notifications]
  → 🟦 Workspaces (find_agent_session_by_name)
  → 🔵 Jido.Signal.ID (generates message IDs)

🟪 ArxivSearch (implements Jido.Action directly)
  → 🟦 Artifact (emit) → returns Jido.Agent.Directive.Emit

⬜ GeneralAgent / ArxivAgent (use Jido.AI.Agent directly)
  → 🟦 TellAction, StreamingPlugin, ArtifactPlugin, MessageInjector
  → 🟩 AddTask, UpdateTask, ListTasks
  → 🟪 ArxivSearch, DisplayPaper
  → 🔵 All agent config (tools, plugins, etc.) uses Jido.AI.Agent DSL
```

**The 🔵 markers show:** Jido is not an implementation detail hidden behind the workbench — it's the foundation that everything builds on. After extraction, every 🔵 dependency stays exactly as it is.

## Appendix B: Consumer App Skeleton (Jido-Native)

After extraction, a new consumer project would look like:

```
my_agent_app/
├── lib/
│   ├── my_agent_app/
│   │   ├── application.ex          # Start Repo, PubSub, Workbench, Jido
│   │   ├── repo.ex                 # Ecto.Repo
│   │   ├── jido.ex                 # use Jido — DIRECT Jido integration
│   │   └── agents/
│   │       ├── customer_support.ex # use Jido.AI.Agent — DIRECT Jido agent
│   │       └── billing_agent.ex    # use Jido.AI.Agent — DIRECT Jido agent
│   ├── my_agent_app_web/
│   │   ├── live/
│   │   │   └── workspace_live.ex   # Uses workbench components + direct Jido
│   │   └── router.ex
├── config/
│   └── config.exs                  # Configure jido_workbench + jido
├── mix.exs                         # Depends on jido_workbench + jido
└── priv/
    └── repo/migrations/            # Generated by mix jido_workbench.install
```

**mix.exs — note explicit Jido deps alongside workbench:**
```elixir
defp deps do
  [
    # Jido ecosystem — consumer depends on these DIRECTLY
    {:jido, "~> 2.0"},
    {:jido_ai, "~> 2.0"},
    {:jido_action, "~> 2.0"},
    {:jido_signal, "~> 2.0"},

    # Workbench — reusable Jido components
    {:jido_workbench, "~> 0.1"},
    {:jido_tasks_plugin, "~> 0.1"},

    # Phoenix
    {:phoenix, "~> 1.8"},
    {:phoenix_live_view, "~> 1.1"},
    ...
  ]
end
```

**jido.ex — consumer's own Jido bootstrap, using workbench storage:**
```elixir
defmodule MyAgentApp.Jido do
  # Direct Jido usage — NOT through workbench
  use Jido,
    otp_app: :my_agent_app,
    storage: {JidoWorkbench.Storage.Ecto, []}  # ← workbench provides the adapter
end
```

**agents/customer_support.ex — pure Jido.AI.Agent with workbench + plugin tools:**
```elixir
defmodule MyAgentApp.Agents.CustomerSupport do
  # Direct Jido agent definition
  use Jido.AI.Agent,
    name: "customer_support",
    description: "Handles customer inquiries with empathy",
    model: :capable,
    tools: [
      # From jido_workbench — these are Jido.Action modules
      JidoWorkbench.TellAction,

      # From jido_tasks_plugin — also Jido.Action modules
      JidoTasksPlugin.Tools.AddTask,
      JidoTasksPlugin.Tools.ListTasks,

      # Consumer's own Jido.Action — sits alongside seamlessly
      MyAgentApp.Tools.LookupCustomer,
      MyAgentApp.Tools.CreateTicket
    ],
    plugins: [
      # From jido_workbench — these are Jido.Plugin modules
      JidoWorkbench.StreamingPlugin,
      JidoWorkbench.ArtifactPlugin,

      # Consumer's own Jido.Plugin — sits alongside seamlessly
      MyAgentApp.Plugins.MetricsPlugin
    ],
    request_transformer: JidoWorkbench.MessageInjector,
    system_prompt: "You are a customer support agent..."

  # Only workbench-specific addition
  def catalog_meta, do: %{color: "blue"}
end
```

**config.exs:**
```elixir
# Jido configuration — consumer's direct relationship with Jido
config :jido,
  actions: [default_timeout: 30_000]

config :jido_ai,
  model_aliases: %{
    capable: "anthropic:claude-sonnet-4-20250514",
    fast: "openai:gpt-5-mini"
  }

# Workbench configuration — tells workbench about consumer's app modules
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
    "tickets" => MyAgentApp.Components.TicketList
  }
```

**The key takeaway:** This consumer app is a **Jido project** that happens to use workbench components. If the consumer wants to do something the workbench doesn't support, they use Jido directly — no permission needed, no wrapper to bypass.
