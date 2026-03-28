# Murmur → Modular Hex Packages: Refactoring Plan

## Executive Summary

This document maps out the extraction of Murmur's multi-agent architecture into reusable Hex packages, organized as a **Mix umbrella project**. The core packages are `jido_murmur` (backend orchestration, Jido components, Ecto schemas) and `jido_murmur_web` (optional LiveView components). Domain-specific tool packages like `jido_arxiv` and `jido_tasks` are published independently to Hex. The current Murmur application remains in the umbrella as a **demo/reference app** that depends on all packages.

**Critical design principle:** Our hex packages must **not** abstract away Jido. Consumer projects are Jido projects. The packages we extract provide **pre-built Jido components** (actions, plugins, storage adapters, LiveView helpers) that consumers compose using Jido's own APIs. Jido types (`Signal`, `Thread`, `Agent`, `Action`, `Plugin`) are first-class citizens throughout — never wrapped, never hidden. This ensures consumer projects can always reach down to Jido when they need to, and that improvements to Jido flow through to everyone seamlessly.

---

## 1. Design Philosophy: Jido-Native, Not Jido-Wrapping

### 1.1 The Anti-Pattern: Abstraction Walls

A naïve extraction would create wrapper behaviours that hide Jido:

```
Consumer App → JidoMurmur wrapper API → Jido (hidden)
```

This is wrong because:
- Consumers **lose access** to Jido features not exposed by the wrapper
- Every new Jido feature requires a corresponding wrapper update
- Consumers can't use Jido documentation directly — they need jido_murmur-specific docs
- Two parallel APIs to learn and maintain
- Breaks when Jido evolves (wrapper lags behind)

### 1.2 The Correct Pattern: Jido Extension

Our packages should sit **alongside** Jido, not on top of it:

```
Consumer App → Jido (direct)
             → JidoMurmur (reusable Jido components)
             → Jido Plugins (reusable Jido actions/plugins)
```

**Concretely, this means:**

| Do This (Jido-Native) | Not This (Jido-Wrapping) |
|---|---|
| Consumers `use Jido.AI.Agent` directly | Don't create `JidoMurmur.Agent` wrapper |
| Plugins implement `Jido.Plugin` directly | Don't create `JidoMurmur.Plugin` wrapper behaviour |
| Tools implement `Jido.Action` directly | Don't create `JidoMurmur.Action` wrapper |
| Storage adapters implement `Jido.Storage` directly | Don't create `JidoMurmur.Storage` wrapper |
| PubSub broadcasts carry `Jido.Signal` structs | Don't strip signals into custom tuples |
| Consumers call `Jido.AgentServer.state(pid)` if they need agent state | Don't hide agent access behind a facade that prevents direct use |
| Consumer request transformers implement `Jido.AI.Reasoning.ReAct.RequestTransformer` | Don't wrap it in a jido_murmur-specific behaviour |

### 1.3 What JidoMurmur Actually Provides

JidoMurmur is a **collection of pre-built, reusable Jido components**:

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

✅ **Good:** Consumer writes a custom `Jido.Plugin` and adds it alongside `JidoMurmur.StreamingPlugin` in their agent's plugin list — works seamlessly because we use Jido's native plugin system.

✅ **Good:** Consumer calls `Jido.AgentServer.state(pid)` to inspect agent internals for debugging — works because we don't hide the pid.

✅ **Good:** Consumer implements `Jido.Storage` for Redis instead of Ecto — works because we don't wrap the storage interface.

✅ **Good:** Consumer writes a custom `Jido.AI.Reasoning.ReAct.RequestTransformer` that composes with ours — works because we implement the standard Jido interface.

❌ **Bad:** Consumer wants to use a new Jido signal type but our `JidoMurmur.Plugin` wrapper behaviour doesn't expose it — they're blocked until we update.

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

7. **Workspace/Session management is semi-generic** — the concept of "workspaces containing agent sessions" is reusable. The hardcoded max-8-agents constraint is being removed.

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

### 3.1 Umbrella Structure

All packages live in a single repository as a **Mix umbrella project** (`mix new murmur --umbrella`). This gives us first-class tooling support — `mix test` from root runs all tests, `mix compile` catches cross-package breakage, and `mix cmd` allows targeted operations — while still allowing each app under `apps/` to be published independently to Hex.

```
murmur/                                   ← umbrella root
├── apps/
│   ├── jido_murmur/                      ← Core backend: orchestration, Jido components, Ecto schemas
│   │   ├── lib/jido_murmur/
│   │   ├── mix.exs                       ← {:jido_murmur, "~> 0.1"} on Hex
│   │   └── test/
│   │
│   ├── jido_murmur_web/                  ← Optional LiveView components (chat, artifacts, etc.)
│   │   ├── lib/jido_murmur_web/
│   │   ├── mix.exs                       ← {:jido_murmur_web, "~> 0.1"} on Hex
│   │   └── test/
│   │
│   ├── jido_tasks/                       ← Task management tools (Jido.Action modules + Ecto schema)
│   │   ├── lib/jido_tasks/
│   │   ├── mix.exs                       ← {:jido_tasks, "~> 0.1"} on Hex
│   │   └── test/
│   │
│   ├── jido_arxiv/                       ← arXiv search tools (Jido.Action modules)
│   │   ├── lib/jido_arxiv/
│   │   ├── mix.exs                       ← {:jido_arxiv, "~> 0.1"} on Hex
│   │   └── test/
│   │
│   └── murmur_demo/                      ← Current Murmur app lives here as a demo/reference project
│       ├── lib/murmur/
│       ├── lib/murmur_web/
│       ├── mix.exs                       ← depends on siblings via in_umbrella: true
│       └── test/
│
├── config/                               ← shared config (scoped per-app: config :jido_murmur, ...)
├── mix.exs                               ← umbrella root mix.exs
├── mix.lock                              ← single shared lockfile
├── .github/                              ← CI for entire umbrella
└── README.md
```

**Why umbrella:**
- **First-class Mix support** — `mix test` from root runs all tests; `mix test --app jido_arxiv` tests a single app; `mix compile` from root catches cross-package breakage automatically
- **Single `mix.lock`** — all apps use the same version of every shared dependency (Phoenix, Ecto, Jido, etc.), preventing "works in jido_murmur but breaks in demo" version skew
- **`in_umbrella: true`** for inter-app deps during development — cleaner than `path:` references
- Single PR for cross-package changes (e.g., renaming a PubSub topic)
- Demo app always tests against latest package code
- No git submodule pain
- CI runs all package tests together with zero custom scripts

**Separate Hex publishing still works:** Each app under `apps/` has its own `mix.exs` with full Hex metadata. Publishing is simply `cd apps/jido_arxiv && mix hex.publish`. A consumer who does `{:jido_arxiv, "~> 0.1"}` gets only that package — the umbrella structure is invisible to them. This means a developer interested only in the arXiv plugin can depend on just `jido_arxiv` without pulling in the rest.

**Inter-app deps during development vs publishing:** During development inside the umbrella, inter-app dependencies use `in_umbrella: true`. For Hex publishing, these are switched to versioned Hex deps (e.g., `{:jido_murmur, "~> 0.1"}`). A Mix alias or release script automates this swap — it's a well-trodden pattern in the Elixir ecosystem.

**Shared `mix.lock` is a feature, not a bug:** Since most consumers will upgrade all murmur packages together at once, having a single lockfile that ensures all packages are tested against the same dependency versions is exactly what we want. It catches incompatibilities at development time rather than in consumer projects.

### 3.2 Consumer-Facing Package Diagram

```
┌────────────────────────────────────────────────────────────────────┐
│                    Consumer Application                             │
│  (or the murmur_demo/ app in the umbrella)                         │
│                                                                     │
│  ┌──────────────┐  ┌───────────────┐  ┌────────────────────────┐  │
│  │ App Agents   │  │ App Frontend  │  │ App Business Logic     │  │
│  │ (use         │  │ (LiveViews,   │  │ (custom contexts,      │  │
│  │  Jido.AI.    │  │  templates)   │  │  schemas, etc.)        │  │
│  │  Agent)      │  │               │  │                        │  │
│  └──────┬───────┘  └──────┬────────┘  └────────────────────────┘  │
│         │                  │                                        │
│  ┌──────┴──────────────────┴───────────────────────────────────┐   │
│  │          jido_murmur (backend orchestration)                │   │
│  │  Pre-built Jido.Plugin, Jido.Action, Jido.Storage adapter   │   │
│  │  Runner, PendingQueue, Catalog, AgentHelper                 │   │
│  │  Workspace/Session Ecto schemas                              │   │
│  │  ComposableRequestTransformer, MessageInjector               │   │
│  └──────────────────────┬──────────────────────────────────────┘   │
│                          │                                          │
│  ┌──────────────────────┴──────────────────────────────────────┐   │
│  │        jido_murmur_web (optional LiveView components)       │   │
│  │  ChatMessage · ChatStream · AgentHeader · MessageInput      │   │
│  │  ArtifactPanel · StreamingIndicator · WorkspaceList         │   │
│  │  ← Consumer can use these OR build their own UI             │   │
│  │  ← Install generators copy components into consumer app     │   │
│  └──────────────────────┬──────────────────────────────────────┘   │
│                          │                                          │
│  ┌──────────────────────┴──────────────────────────────────────┐   │
│  │        Optional Tool Packages (Jido.Action modules)         │   │
│  │        jido_tasks · jido_arxiv · (future packages)          │   │
│  └──────────────────────┬──────────────────────────────────────┘   │
│                          │                                          │
│  ┌──────────────────────┴──────────────────────────────────────┐   │
│  │              jido ecosystem (foundation)                      │   │
│  │  jido · jido_ai · jido_signal · jido_action · req_llm       │   │
│  │                                                               │   │
│  │  Consumer projects use Jido DIRECTLY — our packages           │   │
│  │  sit alongside, not on top.                                   │   │
│  └───────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

**Key difference from a naïve extraction:** The consumer application has arrows going **directly to Jido** as well as to jido_murmur. JidoMurmur does not sit between the consumer and Jido — it sits beside it.

### 3.3 Package Definitions

#### Package 1: `jido_murmur` (Core Backend — Orchestration + Jido Components)

**Purpose:** Backend-only package. Pre-built Jido components for multi-agent workspace applications. Does NOT wrap or replace Jido APIs. Does NOT include any LiveView/web dependencies.

**What it provides (all Jido-native):**

| Component | Jido Interface | What Consumer Does |
|---|---|---|
| `StreamingPlugin` | `Jido.Plugin` | Adds to agent's `plugins:` list |
| `ArtifactPlugin` | `Jido.Plugin` | Adds to agent's `plugins:` list |
| `TellAction` | `Jido.Action` | Adds to agent's `tools:` list |
| `StoreArtifact` | `Jido.Action` | Used internally by ArtifactPlugin |
| `MessageInjector` | `ReAct.RequestTransformer` | Chains via `ComposableRequestTransformer` |
| `ComposableRequestTransformer` | `ReAct.RequestTransformer` | Composes multiple transformers |
| `Storage.Ecto` | `Jido.Storage` | Configures in `use Jido, storage: {...}` |
| Runner, PendingQueue | Uses Jido APIs internally | Consumer calls `Runner.send_message/2` |
| Workspace, AgentSession | Ecto schemas | Consumer uses for data management |

**What consumers still do directly with Jido:**
- `use Jido.AI.Agent` to define agents (with our plugins/tools in the lists)
- `use Jido, otp_app: :my_app, storage: {JidoMurmur.Storage.Ecto, []}` to bootstrap
- Call `Jido.AgentServer.state(pid)` when they need direct agent state access
- Write custom `Jido.Plugin` modules alongside ours
- Write custom `Jido.Action` tools alongside ours
- Implement `Jido.Storage` for non-Ecto backends if needed

**Dependencies:**
- `jido`, `jido_ai`, `jido_signal`, `jido_action`, `req_llm`
- `phoenix_pubsub`, `phoenix_ecto`, `ecto_sql`, `postgrex`, `jason`
- **No** `phoenix` or `phoenix_live_view` — web components live in `jido_murmur_web`

---

#### Package 2: `jido_murmur_web` (Optional LiveView Components)

**Purpose:** Reusable LiveView components for multi-agent chat UIs. Depends on `jido_murmur` for backend. **Fully optional** — consumers can build their own frontend using `jido_murmur`'s backend APIs directly.

**Component delivery strategy (shadcn-inspired):**

LiveView components are tightly coupled to styling and markup. Rather than forcing consumers to override deeply nested component trees, we offer two modes:

1. **Direct use** — Import components from the package:
   ```elixir
   # In consumer's LiveView
   import JidoMurmurWeb.Components.Chat
   ```
   Works if the consumer is happy with the default styling. Tailwind classes are used, so consumers need the `@source` directive in their `app.css`.

2. **Generator-based install** (shadcn approach) — Copy component source into the consumer's project:
   ```bash
   mix jido_murmur_web.install chat
   # Copies ChatMessage, ChatStream, MessageInput, StreamingIndicator
   # into lib/my_app_web/components/jido_murmur/

   mix jido_murmur_web.install artifacts
   # Copies ArtifactPanel, artifact renderers

   mix jido_murmur_web.install all
   # Copies everything
   ```

   This works well with LiveView because:
   - HEEx templates are self-contained — no build step like JSX
   - Components are just `Phoenix.Component` modules — consumer can edit them freely
   - The generator creates a manifest file so `mix jido_murmur_web.update` can show diffs when the upstream package has new versions
   - Consumer owns the code after install — full customization freedom

**Contains:**
- `JidoMurmurWeb.Components.ChatMessage` — single message bubble
- `JidoMurmurWeb.Components.ChatStream` — message list with streaming
- `JidoMurmurWeb.Components.AgentHeader` — agent name/status header
- `JidoMurmurWeb.Components.MessageInput` — message input form
- `JidoMurmurWeb.Components.StreamingIndicator` — thinking/tool_call/usage display
- `JidoMurmurWeb.Components.AgentSelector` — add agent to workspace
- `JidoMurmurWeb.Components.WorkspaceList` — workspace listing
- `JidoMurmurWeb.Components.ArtifactPanel` — artifact tab panel (with renderer dispatch)
- Layout helpers (split view, unified view)
- Install generators (`mix jido_murmur_web.install`)

**Dependencies:**
- `jido_murmur`, `phoenix`, `phoenix_live_view`, `phoenix_html`

---

#### Package 3: `jido_tasks` (Task Management — Jido.Action Tools)

**Purpose:** Kanban-style task board for multi-agent collaboration. Ships as `Jido.Action` modules that consumers add to their agents.

**Contains:**
- `JidoTasks.Tools.AddTask` — `Jido.Action` implementation
- `JidoTasks.Tools.UpdateTask` — `Jido.Action` implementation
- `JidoTasks.Tools.ListTasks` — `Jido.Action` implementation
- `JidoTasks.Task` — Ecto schema
- `JidoTasks.Tasks` — Context (CRUD, filtering, stats)
- `JidoTasks.Components.TaskBoard` — LiveView component
- Migration templates

**How consumers use it (Jido-native composition):**
```elixir
# Consumer agent — tools from the plugin go directly into Jido.AI.Agent tools list
defmodule MyApp.Agents.ProjectManager do
  use Jido.AI.Agent,
    name: "project_manager",
    tools: [
      JidoTasks.Tools.AddTask,      # ← From plugin
      JidoTasks.Tools.UpdateTask,    # ← From plugin
      JidoTasks.Tools.ListTasks,     # ← From plugin
      JidoMurmur.TellAction,            # ← From jido_murmur
      MyApp.Tools.CustomTool               # ← Consumer's own Jido.Action
    ],
    plugins: [
      JidoMurmur.StreamingPlugin,       # ← From jido_murmur
      JidoMurmur.ArtifactPlugin         # ← From jido_murmur
    ],
    request_transformer: JidoMurmur.MessageInjector,
    model: :fast,
    system_prompt: "You are a project manager..."
end
```

Note: The consumer's agent definition is pure Jido. Plugin tools are just `Jido.Action` modules — they compose seamlessly with consumer-written tools and jido_murmur tools.

**Dependencies:**
- `jido_murmur`, `jido_action`, `ecto_sql`

---

#### Package 4: `jido_arxiv` (Academic Research — Jido.Action Tools)

**Purpose:** arXiv paper search and display for research-oriented agents. Ships as `Jido.Action` modules.

**Contains:**
- `JidoArxiv.Tools.ArxivSearch` — `Jido.Action` that emits `Jido.Agent.Directive.Emit` for artifact signals
- `JidoArxiv.Tools.DisplayPaper` — `Jido.Action` implementation
- `JidoArxiv.Components.PaperList` — LiveView component
- `JidoArxiv.Components.PdfViewer` — LiveView component

**Dependencies:**
- `jido_murmur` (for `JidoMurmur.Artifact` emit helper), `jido_action`, `req`, `sweet_xml`

**Note:** The ArxivSearch tool uses `JidoMurmur.Artifact.emit/4` which returns a `Jido.Agent.Directive.Emit` — this is a standard Jido directive. The jido_murmur helper simply makes it convenient to construct the signal; consumers could construct the directive manually using Jido APIs if they preferred.

---

#### Future Tool Packages (examples):
- `jido_web_search` — Web search tools
- `jido_code` — Code execution/analysis tools
- `jido_calendar` — Calendar/scheduling tools
- `jido_email` — Email drafting/sending tools

---

## 4. Detailed Extraction Plan: `jido_murmur`

### 4.1 Module Mapping

| Current Module | New Module | Notes |
|---|---|---|
| `Murmur.Agents.Runner` | `JidoMurmur.Runner` | Core orchestration |
| `Murmur.Agents.PendingQueue` | `JidoMurmur.PendingQueue` | ETS message queue |
| `Murmur.Agents.TableOwner` | `JidoMurmur.TableOwner` | ETS lifecycle |
| `Murmur.Agents.MessageInjector` | `JidoMurmur.MessageInjector` | Request transformer |
| `Murmur.Agents.TeamInstructions` | `JidoMurmur.TeamInstructions` | Collaboration prompt |
| `Murmur.Agents.StreamingPlugin` | `JidoMurmur.StreamingPlugin` | Signal forwarder |
| `Murmur.Agents.ArtifactPlugin` | `JidoMurmur.ArtifactPlugin` | Artifact handler |
| `Murmur.Agents.Artifact` | `JidoMurmur.Artifact` | Artifact helpers |
| `Murmur.Agents.Actions.StoreArtifact` | `JidoMurmur.Actions.StoreArtifact` | Artifact persistence |
| `Murmur.Agents.TellAction` | `JidoMurmur.TellAction` | Inter-agent comms |
| `Murmur.Agents.Catalog` | `JidoMurmur.Catalog` | Profile registry |
| `Murmur.Agents.UITurn` | `JidoMurmur.UITurn` | Thread → UI projection |
| `Murmur.Agents.LLM` | `JidoMurmur.LLM` | Adapter behaviour |
| `Murmur.Agents.LLM.Real` | `JidoMurmur.LLM.Real` | Production adapter |
| `Murmur.Storage.Ecto` | `JidoMurmur.Storage.Ecto` | Jido.Storage impl |
| `Murmur.Storage.Checkpoint` | `JidoMurmur.Storage.Checkpoint` | Schema |
| `Murmur.Storage.ThreadEntry` | `JidoMurmur.Storage.ThreadEntry` | Schema |
| `Murmur.Workspaces` | `JidoMurmur.Workspaces` | Context |
| `Murmur.Workspaces.Workspace` | `JidoMurmur.Workspaces.Workspace` | Schema |
| `Murmur.Workspaces.AgentSession` | `JidoMurmur.Workspaces.AgentSession` | Schema |
| `Murmur.Jido` | *Consumer defines* | `use Jido` stays in app |
| `Murmur.Repo` | *Consumer defines* | Ecto.Repo stays in app |

### 4.2 Design Decisions: Jido-Native Abstractions

The abstractions we introduce must **extend** Jido, not replace it. Here's what we introduce and — critically — what we do NOT introduce.

#### 4.2.1 Configuration Module (Required — app-specific references)

The package needs to access the consuming application's Repo, Jido module, and PubSub without hardcoding. This is the one non-Jido abstraction that's genuinely necessary:

```elixir
defmodule JidoMurmur do
  @moduledoc """
  Configuration for JidoMurmur.

  This module provides access to application-specific modules (Repo, PubSub, etc.)
  that jido_murmur needs to interact with. It does NOT wrap or replace any Jido APIs.
  """

  def repo, do: Application.fetch_env!(:jido_murmur, :repo)
  def jido, do: Application.fetch_env!(:jido_murmur, :jido)
  def pubsub, do: Application.fetch_env!(:jido_murmur, :pubsub)
end
```

Consumer configures in `config.exs`:
```elixir
config :jido_murmur,
  repo: MyApp.Repo,
  jido: MyApp.Jido,
  pubsub: MyApp.PubSub,
  otp_app: :my_app
```

#### 4.2.2 Catalog — Profile Registry (Config-Driven, Not a New Behaviour)

Currently profiles (GeneralAgent, ArxivAgent) are hardcoded in the Catalog. We make it configuration-driven. 

**We do NOT create a `JidoMurmur.AgentProfile` behaviour.** Agent profiles are already defined using `use Jido.AI.Agent` — we should not create a parallel behaviour. Instead, we require that profile modules implement a single function `catalog_meta/0` which is already the pattern used in the codebase:

```elixir
# This is all the "contract" we need — a convention, not a behaviour
# The module is already a Jido.AI.Agent, which defines name/0 and description/0
# We just need catalog_meta/0 for UI metadata (color, icon, etc.)
defmodule MyApp.Agents.CustomerSupport do
  use Jido.AI.Agent,
    name: "customer_support",
    description: "Handles customer inquiries",
    model: :fast,
    tools: [JidoMurmur.TellAction, JidoTasks.Tools.AddTask],
    plugins: [JidoMurmur.StreamingPlugin, JidoMurmur.ArtifactPlugin],
    request_transformer: JidoMurmur.MessageInjector,
    system_prompt: "You are a customer support agent..."

  # Only addition for jido_murmur catalog — not a separate behaviour
  def catalog_meta, do: %{color: "blue"}
end
```

Catalog reads profiles from config:
```elixir
config :jido_murmur,
  profiles: [
    MyApp.Agents.CustomerSupport,
    MyApp.Agents.BillingAgent
  ]
```

**Why not a behaviour?** Because `Jido.AI.Agent` already IS the behaviour. Adding `JidoMurmur.AgentProfile` would create a redundant parallel contract. The `catalog_meta/0` convention is lightweight and doesn't require consumers to add another `@behaviour` declaration — they just implement a function.

#### 4.2.3 Workspace Convenience Functions (NOT a Facade That Hides Jido)

The current WorkspaceLive directly calls `Jido.AgentServer.state(pid)`, `Murmur.Jido.start_agent()`, etc. The previous version of this plan proposed a "WorkspaceFacade" that would hide all Jido access. **That was wrong.**

Instead, we provide **convenience functions** that make common operations easy while leaving Jido fully accessible:

```elixir
defmodule JidoMurmur.AgentHelper do
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
  # Use jido_murmur helper for common setup
  {:ok, pid} = JidoMurmur.AgentHelper.ensure_agent_started(session)
  messages = JidoMurmur.AgentHelper.load_messages(session)

  # BUT consumer can also call Jido directly for advanced features
  {:ok, %{agent: agent}} = Jido.AgentServer.state(pid)
  custom_data = agent.state.my_custom_field  # Direct Jido state access

  {:ok, assign(socket, messages: messages, custom_data: custom_data)}
end
```

#### 4.2.4 Artifact Renderer Registry (Config, Not Behaviour)

Currently artifact rendering is hardcoded. We make it configurable, but keep it simple — a config map, not a new behaviour:

```elixir
config :jido_murmur,
  artifact_renderers: %{
    "papers" => JidoArxiv.Components.PaperList,
    "displayed_paper" => JidoArxiv.Components.PdfViewer,
    "tasks" => JidoTasks.Components.TaskBoard
  }
```

Renderer modules just need to export `badge/1` and `detail/1` function components. This is a **convention**, not a behaviour — no `@behaviour` declaration needed. If a renderer isn't found, the generic renderer is used.

#### 4.2.5 ComposableRequestTransformer (Chains Multiple Transformers)

Jido currently supports only a single `request_transformer:` per agent. Consumers who want their own transformer alongside `MessageInjector` would be stuck. Rather than waiting for an upstream Jido change, we implement a composing transformer that chains multiple transformers in sequence:

```elixir
defmodule JidoMurmur.ComposableRequestTransformer do
  @moduledoc """
  A ReAct.RequestTransformer that composes multiple transformers in sequence.

  Each transformer in the chain receives the request (with any modifications
  from prior transformers applied) and can return additional overrides.
  Overrides are deep-merged in order.

  This is itself a standard Jido ReAct.RequestTransformer — it implements
  the behaviour directly. When Jido adds native multi-transformer support,
  consumers can migrate away from this module with no other changes.
  """

  @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

  @impl true
  def transform_request(request, state, config, runtime_context) do
    transformers = runtime_context[:request_transformers] || config[:request_transformers] || []

    Enum.reduce_while(transformers, {:ok, %{}}, fn transformer, {:ok, acc_overrides} ->
      # Apply accumulated overrides to the request before passing to next transformer
      merged_request = deep_merge_request(request, acc_overrides)

      case transformer.transform_request(merged_request, state, config, runtime_context) do
        {:ok, new_overrides} ->
          {:cont, {:ok, deep_merge(acc_overrides, new_overrides)}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp deep_merge_request(request, overrides) do
    Map.merge(request, overrides, fn
      :messages, base, override -> override  # messages are replaced wholesale
      _key, _base, override -> override
    end)
  end

  defp deep_merge(map1, map2) do
    Map.merge(map1, map2, fn
      _key, v1, v2 when is_map(v1) and is_map(v2) -> deep_merge(v1, v2)
      _key, _v1, v2 -> v2
    end)
  end
end
```

**Consumer usage — composing MessageInjector with a custom transformer:**

```elixir
defmodule MyApp.Agents.CustomAgent do
  use Jido.AI.Agent,
    name: "custom_agent",
    # Use the composable transformer as the single entry point
    request_transformer: JidoMurmur.ComposableRequestTransformer,
    tools: [JidoMurmur.TellAction],
    plugins: [JidoMurmur.StreamingPlugin],
    model: :fast,
    system_prompt: "You are an agent..."

  # The composable transformer reads the chain from runtime_context or config
  def config do
    %{
      request_transformers: [
        JidoMurmur.MessageInjector,          # Team instructions + pending messages
        MyApp.Transformers.AuditTransformer   # Consumer's own transformer
      ]
    }
  end
end
```

**Jido interplay:** This is itself a `ReAct.RequestTransformer` — standard Jido. Each transformer in the chain is also a standard `ReAct.RequestTransformer`. When Jido adds native multi-transformer support upstream, consumers can drop this module and use the native mechanism directly. No lock-in.

**Note:** A Jido issue should be opened to discuss native multi-transformer support. In the meantime, this composable approach is a clean stopgap.

#### 4.2.6 Workspace Schema Flexibility

**Recommendation:** Workspace and AgentSession schemas should be **wrappable, not extensible**.

Extensible schemas (adding custom fields via config or macros) create complex migration stories and fragile code. Instead:

1. **`jido_murmur` schemas are fixed** — they define the core fields needed for workspace/session management and no more.

2. **Consumers create their own schemas that reference ours** — a consumer who needs extra fields creates their own Ecto schema with a `belongs_to` or a 1:1 relationship:

```elixir
# Consumer's extended workspace with custom fields
defmodule MyApp.ProjectWorkspace do
  use Ecto.Schema

  schema "project_workspaces" do
    belongs_to :workspace, JidoMurmur.Workspaces.Workspace
    field :project_code, :string
    field :department, :string
    field :budget_cents, :integer
    timestamps()
  end
end
```

3. **`jido_murmur` schemas include a `metadata` JSONB field** as a lightweight escape hatch for simple key-value extensions without a separate table:

```elixir
# In JidoMurmur.Workspaces.Workspace
field :metadata, :map, default: %{}
```

This approach is the safest because:
- Package migrations never need to know about consumer fields
- Consumers control their own schema evolution
- The `metadata` field handles simple cases without extra tables
- No complex macro/DSL for schema extension that would break on package upgrades

#### 4.2.7 Auth-Ready Schema Design (Future Migration Path)

Authentication is out of scope now, but we design schemas so adding auth later is a **data migration, not a schema redesign**.

**Strategy: scope-ready schemas with optional `owner_id`**

```elixir
# JidoMurmur.Workspaces.Workspace
schema "jido_murmur_workspaces" do
  field :name, :string
  field :metadata, :map, default: %{}

  # Auth-ready: optional foreign key, nil when auth is not configured.
  # When auth is added, consumers run a migration to populate this
  # and add a NOT NULL constraint.
  field :owner_id, :binary_id

  has_many :agent_sessions, JidoMurmur.Workspaces.AgentSession
  timestamps()
end
```

**Pluggable authorization hook:**

```elixir
# In config
config :jido_murmur,
  authorize: nil  # Default: no auth, all operations permitted

# Consumer adds auth later:
config :jido_murmur,
  authorize: MyApp.JidoAuthorize

# Consumer implements:
defmodule MyApp.JidoAuthorize do
  @doc "Return :ok or {:error, :unauthorized}"
  def authorize(action, resource, scope) do
    case {action, resource} do
      {:read, %JidoMurmur.Workspaces.Workspace{owner_id: owner_id}} ->
        if scope.current_user.id == owner_id, do: :ok, else: {:error, :unauthorized}
      _ ->
        :ok
    end
  end
end
```

**How jido_murmur uses it:**

```elixir
# In JidoMurmur.Workspaces context functions
def get_workspace!(id, scope \\ %{}) do
  workspace = repo().get!(Workspace, id)

  case authorize_fn() do
    nil -> workspace
    authorize -> 
      :ok = authorize.authorize(:read, workspace, scope)
      workspace
  end
end

defp authorize_fn, do: Application.get_env(:jido_murmur, :authorize)
```

**Migration path when auth is added:**
1. Consumer adds `owner_id` migration: `ALTER TABLE jido_murmur_workspaces ALTER COLUMN owner_id SET NOT NULL`
2. Consumer configures `authorize: MyApp.JidoAuthorize`
3. Consumer passes `scope` (containing `current_user`) to context functions
4. No schema redesign needed — the column was always there

#### 4.2.8 What We Do NOT Create (Jido Interplay Preservation)

| Rejected Abstraction | Why | What to Do Instead |
|---|---|---|
| `JidoMurmur.AgentProfile` behaviour | Duplicates `Jido.AI.Agent` | Convention: `catalog_meta/0` function |
| `JidoMurmur.Plugin` behaviour for plugin packages | Duplicates `Jido.Plugin` | Plugins just implement `Jido.Plugin` |
| `JidoMurmur.Action` behaviour for tools | Duplicates `Jido.Action` | Tools just implement `Jido.Action` |
| `JidoMurmur.Storage` wrapper | Duplicates `Jido.Storage` | Storage implements `Jido.Storage` directly |
| `JidoMurmur.Signal` wrapper types | Duplicates `Jido.Signal` | Use `Jido.Signal` everywhere |
| WorkspaceFacade that hides pids | Prevents direct Jido access | AgentHelper that returns Jido types |
| Max agents per workspace limit | Artificial constraint | Removed — consumer decides their own limits |

### 4.3 Migration Strategy

#### Database Migrations

`jido_murmur` should ship migration modules that consumers install into their app:

```elixir
# Consumer runs:
mix jido_murmur.install

# This generates into the consumer's priv/repo/migrations/:
# - TIMESTAMP_create_jido_murmur_workspaces.exs
# - TIMESTAMP_create_jido_murmur_agent_sessions.exs
# - TIMESTAMP_create_jido_murmur_checkpoints.exs
# - TIMESTAMP_create_jido_murmur_thread_entries.exs
```

Alternatively, use Ecto's `@migration_source` or provide migration templates that the consumer can customize.

For plugin packages (e.g., `jido_tasks`):
```elixir
mix jido_tasks.install
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

JidoMurmur needs to be startable as part of the consumer's supervision tree:

```elixir
# Consumer's application.ex
children = [
  MyApp.Repo,
  {Phoenix.PubSub, name: MyApp.PubSub},
  {JidoMurmur.Supervisor, []},  # ← Starts TableOwner, etc.
  MyAppWeb.Endpoint,
  MyApp.Jido
]
```

`JidoMurmur.Supervisor` manages:
- `JidoMurmur.TableOwner` (ETS tables)
- Any future jido_murmur-specific processes

---

## 5. Detailed Extraction Plan: Plugin Packages

### 5.1 `jido_tasks`

```
jido_tasks/
├── lib/
│   ├── jido_tasks.ex              # Module docs + version
│   ├── jido_tasks/
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

### 5.2 `jido_arxiv`

```
jido_arxiv/
├── lib/
│   ├── jido_arxiv.ex
│   ├── jido_arxiv/
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
6. **No `JidoMurmur.Plugin` meta-behaviour** — plugins are just collections of Jido components

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
      # From jido_murmur
      JidoMurmur.TellAction,

      # From jido_tasks
      JidoTasks.Tools.AddTask,
      JidoTasks.Tools.UpdateTask,
      JidoTasks.Tools.ListTasks,

      # From jido_arxiv
      JidoArxiv.Tools.ArxivSearch,
      JidoArxiv.Tools.DisplayPaper,

      # Consumer's own custom tools (also Jido.Action)
      MyApp.Tools.SummarizeDocument
    ],
    plugins: [
      # From jido_murmur
      JidoMurmur.StreamingPlugin,
      JidoMurmur.ArtifactPlugin,

      # Consumer's own custom plugins (also Jido.Plugin)
      MyApp.Plugins.AuditLogPlugin
    ],
    request_transformer: JidoMurmur.ComposableRequestTransformer,
    system_prompt: "You are a research assistant..."

  def config do
    %{request_transformers: [JidoMurmur.MessageInjector]}
  end

  def catalog_meta, do: %{color: "violet"}
end
```

This is pure Jido composition. The consumer doesn't need to learn any jido_murmur-specific APIs for agent definition — just standard `Jido.AI.Agent`.

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

Level 1a: JidoMurmur — REUSABLE JIDO COMPONENTS (backend)
  ├── Pre-built Jido.Plugin modules (StreamingPlugin, ArtifactPlugin)
  ├── Pre-built Jido.Action modules (TellAction, StoreArtifact)
  ├── Pre-built Jido.Storage adapter (Storage.Ecto)
  ├── Pre-built ReAct.RequestTransformer (MessageInjector, ComposableRequestTransformer)
  ├── Orchestration helpers (Runner, PendingQueue, TeamInstructions)
  ├── Convenience functions (AgentHelper — returns Jido types)
  ├── Ecto schemas (Workspace, AgentSession — auth-ready with optional owner_id)
  ├── Configuration contract (repo, jido, pubsub, profiles, authorize)
  └── PubSub topic/message contracts (carry Jido.Signal structs)

Level 1b: JidoMurmurWeb — OPTIONAL LIVEVIEW COMPONENTS
  ├── Chat, artifact, workspace components
  ├── Install generators (shadcn-style copy into consumer project)
  └── Depends on Level 1a only

Level 2: Tool Packages — ADDITIONAL JIDO COMPONENTS
  ├── Additional Jido.Action tools (AddTask, ArxivSearch, etc.)
  ├── Additional LiveView components (domain-specific)
  ├── Ecto schemas and migration templates
  └── Nothing package-specific that wraps Jido

Level 3: Consumer Application (or demo/ app)
  ├── use Jido.AI.Agent (DIRECT — not through jido_murmur)
  ├── use Jido, storage: {JidoMurmur.Storage.Ecto, []} (DIRECT)
  ├── Compose tools/plugins from all levels
  ├── Write custom Jido.Action / Jido.Plugin modules
  ├── Call Jido APIs directly alongside jido_murmur helpers
  └── Build custom LiveViews (with or without jido_murmur_web components)
```

**Key insight:** Levels 1 and 2 provide **implementations** of Level 0 interfaces. Level 3 **uses** Level 0 directly and picks implementations from Levels 1 and 2. There is no separate "jido_murmur API" layer between the consumer and Jido.

### 6.2 Versioning Strategy

**Semantic Versioning with these rules:**

- **Patch (0.x.Y):** Bug fixes, performance improvements, no API changes
- **Minor (0.X.0):** New features, new optional configuration, backward-compatible changes
- **Major (X.0.0):** Breaking changes to jido_murmur-specific contracts (below)

**jido_murmur-specific contracts that require major version bumps to break:**

1. Configuration keys and expected value shapes (`config :jido_murmur, ...`)
2. PubSub topic patterns and message tuple shapes
3. `JidoMurmur.AgentHelper` public function signatures
4. `JidoMurmur.ComposableRequestTransformer` chaining semantics
5. Database table schemas (migrations should always be additive)
6. `catalog_meta/0` convention expectations
7. `authorize` hook interface

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
  ├── CAN depend on: Jido (DIRECT), JidoMurmur, JidoMurmurWeb, tool packages
  ├── CAN call Jido APIs directly (AgentServer, Signal, Thread, etc.)
  ├── CAN write custom Jido.Action / Jido.Plugin alongside jido_murmur ones
  ├── CAN access agent state via Jido.AgentServer.state(pid)
  │
JidoMurmur (backend)
  ├── CAN depend on: Jido ecosystem, Ecto, Phoenix.PubSub
  ├── MUST use Jido types in public API (Signal, Thread, pids)
  ├── MUST NOT wrap or hide Jido types behind jido_murmur-specific types
  ├── MUST NOT depend on Phoenix or Phoenix.LiveView
  ├── CANNOT depend on: Consumer app modules (use config for repo/jido/pubsub)
  │
JidoMurmurWeb (optional LiveView components)
  ├── CAN depend on: JidoMurmur, Phoenix, Phoenix.LiveView
  ├── MUST NOT contain business logic (delegate to JidoMurmur)
  ├── CANNOT depend on: Consumer app modules
  │
Tool Packages (jido_tasks, jido_arxiv, etc.)
  ├── CAN depend on: JidoMurmur, Jido ecosystem
  ├── MUST implement Jido behaviours directly (Action, Plugin)
  ├── MUST NOT create wrapper behaviours
  ├── CANNOT depend on: Consumer app modules, other tool packages
```

---

## 7. Refactoring Execution Plan

### Phase 1: Prepare Codebase In-Place (1-2 weeks)

**Goal:** Create the convenience functions, configuration hooks, and new components within the existing Murmur codebase before restructuring to the umbrella. This de-risks the extraction.

1. **Remove hardcoded max-agents limit**
   - Delete `@max_agents_per_workspace 8` from `Murmur.Workspaces`
   - Remove the `session_count >= @max_agents_per_workspace` guard
   - Remove the `:max_agents_reached` error flash from `WorkspaceLive`
   - Update tests that assert on the 8-agent limit (remove or make them test unlimited)
   - **Test:** All tests pass without the artificial constraint

2. **Implement ComposableRequestTransformer**
   - Create `Murmur.Agents.ComposableRequestTransformer` (implements `ReAct.RequestTransformer`)
   - Chains multiple transformers in sequence, deep-merging overrides
   - Update agent profiles to use it with `MessageInjector` as the first transformer
   - **Test:** Existing message injection tests pass; new tests verify chaining behavior

3. **Create AgentHelper module**
   - Extract common agent operations from `WorkspaceLive` into `Murmur.Agents.AgentHelper`
   - Functions: `ensure_agent_started/1`, `load_messages/1`, `load_artifacts/1`, `subscribe/2`, `cleanup_workspace_storage/1`
   - These functions use Jido APIs internally and **return Jido types** (pids, thread entries, etc.)
   - Update `WorkspaceLive` to use helpers for common operations
   - **Important:** WorkspaceLive can still call Jido directly for anything the helper doesn't cover
   - **Test:** All existing LiveView tests pass without changes

4. **Make Catalog configuration-driven**
   - Move profile list from hardcoded to application config
   - Existing agents already implement `catalog_meta/0` — no behaviour change needed
   - **Test:** Catalog tests pass with configuration-driven profiles

5. **Make artifact rendering configurable**
   - Replace hardcoded dispatch with config-driven registry
   - **Test:** Artifact rendering tests pass

6. **Parameterize app-specific references**
   - Replace all `Murmur.Repo` references with configurable module
   - Replace all `Murmur.Jido` references with configurable module
   - Replace all `Murmur.PubSub` references with configurable module
   - **Test:** All tests pass with the same modules configured via application env

7. **Add auth-ready fields to schemas**
   - Add optional `owner_id` column to workspaces table
   - Add `metadata` JSONB column to workspaces and agent_sessions
   - Add pluggable `authorize` config hook (defaults to nil / no-op)
   - **Test:** Existing tests unaffected (auth disabled by default)

### Phase 2: Restructure to Umbrella (1-2 weeks)

**Goal:** Move code into a Mix umbrella directory structure. All packages coexist in one repo with first-class tooling support.

1. **Create umbrella skeleton** (via `mix new murmur --umbrella`, then add apps)
   ```
   murmur/
   ├── apps/
   │   ├── jido_murmur/
   │   │   ├── lib/jido_murmur.ex
   │   │   ├── lib/jido_murmur/
   │   │   │   ├── composable_request_transformer.ex  # NEW
   │   │   │   ├── agent_helper.ex
   │   │   │   ├── runner.ex
   │   │   │   ├── pending_queue.ex
   │   │   │   ├── table_owner.ex
   │   │   │   ├── message_injector.ex
   │   │   │   ├── team_instructions.ex
   │   │   │   ├── streaming_plugin.ex
   │   │   │   ├── artifact_plugin.ex
   │   │   │   ├── artifact.ex
   │   │   │   ├── tell_action.ex
   │   │   │   ├── catalog.ex
   │   │   │   ├── ui_turn.ex
   │   │   │   ├── llm.ex
   │   │   │   ├── llm/real.ex
   │   │   │   ├── actions/store_artifact.ex
   │   │   │   ├── storage/{ecto,checkpoint,thread_entry}.ex
   │   │   │   ├── workspaces/{workspace,agent_session}.ex
   │   │   │   ├── workspaces.ex
   │   │   │   └── supervisor.ex
   │   │   ├── mix.exs
   │   │   ├── test/
   │   │   └── priv/templates/
   │   │
   │   ├── jido_murmur_web/                    # NEW — split from jido_murmur
   │   │   ├── lib/jido_murmur_web/
   │   │   │   └── components/
   │   │   │       ├── chat_message.ex
   │   │   │       ├── chat_stream.ex
   │   │   │       ├── agent_header.ex
   │   │   │       ├── message_input.ex
   │   │   │       ├── streaming_indicator.ex
   │   │   │       ├── agent_selector.ex
   │   │   │       ├── workspace_list.ex
   │   │   │       └── artifact_panel.ex
   │   │   ├── lib/mix/tasks/
   │   │   │   └── jido_murmur_web.install.ex  # Generator: copies components to consumer
   │   │   ├── mix.exs
   │   │   └── test/
   │   │
   │   ├── jido_tasks/
   │   │   └── ...
   │   │
   │   ├── jido_arxiv/
   │   │   └── ...
   │   │
   │   └── murmur_demo/                         # Current Murmur app (demo/reference)
   │       ├── lib/murmur/
   │       ├── lib/murmur_web/
   │       ├── mix.exs                           # deps: in_umbrella: true
   │       └── test/
   │
   ├── config/                                   # Shared config (scoped per-app)
   ├── mix.exs                                   # Umbrella root
   └── mix.lock                                  # Single shared lockfile
   ```

2. **Move modules into packages** (following the mapping in Section 4.1)
   - All Jido.Plugin/Action/Storage implementations keep their `use Jido.*` macros
   - No wrapper behaviours are introduced
   - All public functions return Jido types where applicable
   - LiveView components go into `jido_murmur_web`, not `jido_murmur`

3. **Create migration generators**
   - `mix jido_murmur.install` — generates workspace/session/storage migrations
   - `mix jido_murmur_web.install` — copies LiveView components into consumer project (shadcn-style)
   - `mix jido_tasks.install` — generates tasks migration

4. **Create test helpers**
   - `JidoMurmur.TestCase` — equivalent of current `AgentCase`
   - Mock LLM helpers (wrapping Mox stubs for `Jido.AI.Agent` ask/await)
   - Helpers use Jido types — consumers test with Jido's own test patterns

5. **Update demo app to depend on umbrella siblings**
   - Add umbrella dependencies: `{:jido_murmur, in_umbrella: true}`
   - Update all module references
   - Remove extracted modules from demo app
   - **Test:** `mix test` from umbrella root — all demo app tests pass

### Phase 3: Extract Tool Packages (1 week each)

1. **Extract `jido_tasks`**
   - Move Task schema, Tasks context, task tools into `apps/jido_tasks/`
   - Create migration generator
   - Update demo app to depend on it

2. **Extract `jido_arxiv`**
   - Move ArxivSearch, DisplayPaper tools into `apps/jido_arxiv/`
   - Move PaperList, PdfViewer components to `jido_arxiv` (these are domain-specific, not generic UI)
   - Update demo app to depend on it

### Phase 4: LiveView Component Library (1-2 weeks)

**Goal:** Extract reusable LiveView components from the demo app's WorkspaceLive into `jido_murmur_web`.

1. **Chat components** (extracted from WorkspaceLive template)
   - `JidoMurmurWeb.Components.ChatMessage` — single message bubble
   - `JidoMurmurWeb.Components.ChatStream` — message list with streaming
   - `JidoMurmurWeb.Components.AgentHeader` — agent name/status header
   - `JidoMurmurWeb.Components.MessageInput` — message input form
   - `JidoMurmurWeb.Components.StreamingIndicator` — thinking/tool_call/usage display

2. **Workspace components**
   - `JidoMurmurWeb.Components.AgentSelector` — add agent to workspace
   - `JidoMurmurWeb.Components.WorkspaceList` — workspace listing
   - `JidoMurmurWeb.Components.ArtifactPanel` — artifact tab panel (with renderer dispatch)

3. **Layout helpers**
   - Split view (multiple agent columns)
   - Unified view (single timeline)

4. **Install generator** (`mix jido_murmur_web.install`)
   - `mix jido_murmur_web.install chat` — copies chat components
   - `mix jido_murmur_web.install artifacts` — copies artifact components
   - `mix jido_murmur_web.install all` — copies everything
   - Creates a manifest for `mix jido_murmur_web.update` to show diffs on upgrade

These components are **opt-in** — consumers can use them directly, install (copy) them for customization, or build their own UI using `jido_murmur`'s backend APIs.

### Phase 5: Validation & Documentation (1 week)

1. **Validate with a second consumer app** (NOT the demo app)
   - Minimal Phoenix app with 1 custom agent profile
   - Depends on `jido_murmur` from Hex (or git)
   - Should take < 1 hour to set up from scratch
   - Tests: define agent, create workspace, send message, see streaming response

2. **Write documentation**
   - Getting started guide
   - Agent profile creation guide
   - Tool package creation guide
   - API reference (ExDoc)
   - Architecture decision records
   - Umbrella development guide (how to develop across apps, publish to Hex)

3. **Publish packages** to Hex.pm
   - `jido_murmur`
   - `jido_murmur_web`
   - `jido_tasks`
   - `jido_arxiv`

---

## 8. Risks & Mitigations

### 8.1 Jido Version Coupling

**Risk:** Since we expose Jido types directly (not wrapped), a breaking change in Jido breaks our consumers too.

**Mitigation:** This is actually a feature — consumers are already Jido projects. When Jido releases a major version, consumers need to upgrade regardless. Our packages declare compatible Jido version ranges in `mix.exs` and we test against Jido's main branch in CI. We upgrade in lockstep because we're part of the Jido ecosystem, not a separate layer.

### 8.2 Circular Dependencies

**Risk:** `TellAction` depends on `Workspaces` context, which depends on `Repo`. If `Repo` is in the consumer app, `TellAction` can't call it directly.

**Mitigation:** All database access goes through the configurable `repo()` function in `JidoMurmur`. The consumer configures their Repo module at startup.

### 8.3 ETS Table Naming Conflicts

**Risk:** Multiple consumer apps running in the same BEAM node could conflict on ETS table names.

**Mitigation:** Namespace ETS tables with the OTP app name: `:jido_murmur_pending_messages` or use `{:via, Registry, {JidoMurmur.Registry, :pending_messages}}`.

### 8.4 PubSub Name Conflicts

**Risk:** Hardcoded PubSub name won't work in multi-app deployments.

**Mitigation:** Already addressed — PubSub module is configurable via application env.

### 8.5 Migration Ordering

**Risk:** Tool package migrations depend on jido_murmur migrations (e.g., tasks table references workspaces table).

**Mitigation:** Migration generator enforces ordering via timestamps. Document dependency chain in installation instructions.

### 8.6 LiveView Component Styling

**Risk:** Tailwind classes from the package may not be picked up by the consumer's CSS build.

**Mitigation:** Two approaches depending on how the consumer uses `jido_murmur_web`:

1. **Direct import mode:** Add `@source` directive to consumer's `app.css`:
```css
@source "../../deps/jido_murmur_web";
@source "../../deps/jido_tasks";
```

2. **Generator-installed mode (shadcn-style):** Components are copied into the consumer's project, so Tailwind picks them up automatically via the existing `@source` for the app's own code. No extra config needed.

### 8.7 Breaking Changes During Early Development

**Risk:** The API will inevitably change as we learn from the first few consumer apps.

**Mitigation:**
- Start at version `0.x.y` to signal instability
- Use `@deprecated` annotations before removing features
- Maintain a CHANGELOG with migration guides
- Consider a `JidoMurmur.Compat` module for backward compatibility shims

---

## 9. Resolved Design Decisions

These decisions were discussed and finalized. They are incorporated throughout the document.

| # | Question | Decision | Where Reflected |
|---|---|---|---|
| 1 | Package naming | **`jido_murmur`** (not `jido_workbench`) | All sections |
| 2 | Monorepo vs multi-repo | **Mix umbrella** with `apps/jido_murmur`, `apps/jido_murmur_web`, `apps/jido_tasks`, `apps/jido_arxiv`, and `apps/murmur_demo` (current Murmur app). Each app published independently to Hex. Umbrella gives first-class `mix test`/`mix compile` from root, shared `mix.lock`, and `in_umbrella: true` deps — while still supporting per-app `cd apps/jido_arxiv && mix hex.publish`. | Section 3.1 |
| 3 | LiveView components | **Opt-in via `jido_murmur_web`**. Two modes: direct import or shadcn-style generator that copies components into consumer project for full customization. | Section 3.3 Package 2, Phase 4 |
| 4 | Workspace schema flexibility | **Wrappable, not extensible.** Fixed schemas with `metadata` JSONB escape hatch. Consumers create their own schemas with `belongs_to` for custom fields. | Section 4.2.6 |
| 5 | Max agents per workspace | **Removed entirely.** The hardcoded limit of 8 should never have been there. Consumer decides their own limits if needed. | Phase 1 step 1, Section 4.2.8 |
| 6 | Authentication | **No auth now, but auth-ready.** Optional `owner_id` column on workspaces. Pluggable `authorize` hook in config (defaults to nil). Clear migration path: populate `owner_id`, add NOT NULL constraint, configure authorize function. | Section 4.2.7 |
| 7 | Multi-tenancy | **Out of scope.** Not addressed in schema design or configuration. | N/A |
| 8 | Jido version pinning | **Loose** (`~> 2.0`). Relies on Jido maintaining backward compatibility. We test against Jido's main branch in CI. | Section 6.2 |
| 9 | Custom RequestTransformers | **`ComposableRequestTransformer`** — a standard `ReAct.RequestTransformer` that chains multiple transformers in sequence, deep-merging overrides. Jido ticket to be opened for native multi-transformer support; this is a clean stopgap. | Section 4.2.5 |

---

## 10. Summary of Deliverables

| Deliverable | Package | Jido Relationship | Priority |
|---|---|---|---|
| `jido_murmur` Hex package | Core backend | Pre-built Jido components (plugins, actions, storage) | P0 — Must have |
| `jido_murmur_web` Hex package | Optional web | LiveView components + install generators | P1 — Should have |
| Umbrella structure with demo app | Infrastructure | Demo app validates all packages | P0 — Must have |
| ComposableRequestTransformer | `jido_murmur` | Chains multiple `ReAct.RequestTransformer` impls | P0 — Must have |
| AgentHelper convenience functions | `jido_murmur` | Returns Jido types (pids, signals) | P0 — Must have |
| Auth-ready schema design | `jido_murmur` | Optional `owner_id` + pluggable `authorize` hook | P0 — Must have |
| Config-driven Catalog | `jido_murmur` | Discovers `Jido.AI.Agent` modules | P0 — Must have |
| Config-driven artifact renderers | `jido_murmur` | N/A (pure UI) | P0 — Must have |
| Migration generators | All packages | Includes Jido storage tables | P0 — Must have |
| `jido_tasks` tool package | Standalone | Ships `Jido.Action` tools | P1 — Should have |
| `jido_arxiv` tool package | Standalone | Ships `Jido.Action` tools | P2 — Nice to have |
| Test helpers | `jido_murmur` | Wraps Mox stubs for Jido APIs | P1 — Should have |
| Getting Started guide | Documentation | Shows Jido-native composition | P0 — Must have |
| Second consumer validation | Validation | Confirms Jido interplay works | P1 — Should have |

---

## Appendix A: Current Coupling Map (Jido Integration Highlighted)

This diagram shows every module-to-module dependency in the current codebase, color-coded by extraction target. Note how Jido is present throughout — this is by design.

```
🟦 = jido_murmur extraction target (backend)
🟧 = jido_murmur_web extraction target (optional LiveView components)
🟩 = jido_tasks extraction target
🟪 = jido_arxiv extraction target
⬜ = stays in demo app (Murmur)
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

**The 🔵 markers show:** Jido is not an implementation detail hidden behind jido_murmur — it's the foundation that everything builds on. After extraction, every 🔵 dependency stays exactly as it is.

## Appendix B: Consumer App Skeleton (Jido-Native)

After extraction, a new consumer project would look like:

```
my_agent_app/
├── lib/
│   ├── my_agent_app/
│   │   ├── application.ex          # Start Repo, PubSub, JidoMurmur.Supervisor, Jido
│   │   ├── repo.ex                 # Ecto.Repo
│   │   ├── jido.ex                 # use Jido — DIRECT Jido integration
│   │   └── agents/
│   │       ├── customer_support.ex # use Jido.AI.Agent — DIRECT Jido agent
│   │       └── billing_agent.ex    # use Jido.AI.Agent — DIRECT Jido agent
│   ├── my_agent_app_web/
│   │   ├── components/
│   │   │   └── jido_murmur/        # ← Copied by `mix jido_murmur_web.install all`
│   │   │       ├── chat_message.ex
│   │   │       ├── chat_stream.ex
│   │   │       └── ...
│   │   ├── live/
│   │   │   └── workspace_live.ex   # Uses installed components + direct Jido
│   │   └── router.ex
├── config/
│   └── config.exs                  # Configure jido_murmur + jido
├── mix.exs                         # Depends on jido_murmur + jido
└── priv/
    └── repo/migrations/            # Generated by mix jido_murmur.install
```

**mix.exs — note explicit Jido deps alongside jido_murmur:**
```elixir
defp deps do
  [
    # Jido ecosystem — consumer depends on these DIRECTLY
    {:jido, "~> 2.0"},
    {:jido_ai, "~> 2.0"},
    {:jido_action, "~> 2.0"},
    {:jido_signal, "~> 2.0"},

    # JidoMurmur — reusable Jido components (backend)
    {:jido_murmur, "~> 0.1"},

    # JidoMurmurWeb — optional LiveView components
    {:jido_murmur_web, "~> 0.1"},

    # Tool packages
    {:jido_tasks, "~> 0.1"},

    # Phoenix
    {:phoenix, "~> 1.8"},
    {:phoenix_live_view, "~> 1.1"},
    ...
  ]
end
```

**jido.ex — consumer's own Jido bootstrap, using jido_murmur storage:**
```elixir
defmodule MyAgentApp.Jido do
  # Direct Jido usage — NOT through jido_murmur
  use Jido,
    otp_app: :my_agent_app,
    storage: {JidoMurmur.Storage.Ecto, []}  # ← jido_murmur provides the adapter
end
```

**agents/customer_support.ex — pure Jido.AI.Agent with ComposableRequestTransformer:**
```elixir
defmodule MyAgentApp.Agents.CustomerSupport do
  # Direct Jido agent definition
  use Jido.AI.Agent,
    name: "customer_support",
    description: "Handles customer inquiries with empathy",
    model: :capable,
    tools: [
      # From jido_murmur — these are Jido.Action modules
      JidoMurmur.TellAction,

      # From jido_tasks — also Jido.Action modules
      JidoTasks.Tools.AddTask,
      JidoTasks.Tools.ListTasks,

      # Consumer's own Jido.Action — sits alongside seamlessly
      MyAgentApp.Tools.LookupCustomer,
      MyAgentApp.Tools.CreateTicket
    ],
    plugins: [
      # From jido_murmur — these are Jido.Plugin modules
      JidoMurmur.StreamingPlugin,
      JidoMurmur.ArtifactPlugin,

      # Consumer's own Jido.Plugin — sits alongside seamlessly
      MyAgentApp.Plugins.MetricsPlugin
    ],
    # Use ComposableRequestTransformer to chain MessageInjector with consumer's own
    request_transformer: JidoMurmur.ComposableRequestTransformer,
    system_prompt: "You are a customer support agent..."

  # ComposableRequestTransformer reads this chain
  def config do
    %{
      request_transformers: [
        JidoMurmur.MessageInjector,            # Team instructions + pending messages
        MyAgentApp.Transformers.ComplianceCheck # Consumer's own transformer
      ]
    }
  end

  # Only jido_murmur-specific addition
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

# JidoMurmur configuration — tells jido_murmur about consumer's app modules
config :jido_murmur,
  repo: MyAgentApp.Repo,
  jido: MyAgentApp.Jido,
  pubsub: MyAgentApp.PubSub,
  otp_app: :my_agent_app,
  authorize: nil,  # No auth yet — add MyAgentApp.JidoAuthorize later
  profiles: [
    MyAgentApp.Agents.CustomerSupport,
    MyAgentApp.Agents.BillingAgent
  ],
  artifact_renderers: %{
    "tickets" => MyAgentApp.Components.TicketList
  }
```

**The key takeaway:** This consumer app is a **Jido project** that happens to use jido_murmur components. If the consumer wants to do something jido_murmur doesn't support, they use Jido directly — no permission needed, no wrapper to bypass.
