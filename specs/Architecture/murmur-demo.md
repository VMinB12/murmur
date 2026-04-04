# murmur_demo — Reference Application

## Purpose

Reference Phoenix 1.8 LiveView application that ties together all Murmur umbrella packages into a working multi-agent chat system. Demonstrates real-time workspaces, agent profiles, streaming, artifact rendering, and task management.

## Routes

| Path | LiveView | Purpose |
|------|----------|---------|
| `/`, `/workspaces` | `WorkspaceListLive` | List/create workspaces |
| `/workspaces/:id` | `WorkspaceLive` | Multi-agent chat interface |
| `/dev/dashboard` | LiveDashboard | Dev metrics (dev only) |

## Agent Profiles

Three pre-built profiles in `Murmur.Agents.Profiles`:

### GeneralAgent

- **Tools:** `TellAction`, `AddTask`, `UpdateTask`, `ListTasks`
- **Plugins:** `StreamingPlugin`, `ArtifactPlugin`
- **Model:** `:fast` (gpt-5-mini)
- Conversational AI with task management

### ArxivAgent

- **Tools:** `TellAction`, `ArxivSearch`, `DisplayPaper`, task tools
- **Plugins:** `StreamingPlugin`, `ArtifactPlugin`
- **Model:** `:fast`
- **Tool timeout:** 300s (long arXiv queries)
- Research assistant with paper discovery

### SqlAgent

- **Tools:** `TellAction`, `SqlQuery`, `SqlDisplay`, task tools
- **Plugins:** `StreamingPlugin`, `ArtifactPlugin`
- **Request transformer:** `JidoSql.RequestTransformer` (schema injection)
- **Model:** `:fast`
- Database query assistant with safety guardrails

## Artifact Renderers

Demo-owned artifact rendering is registered in `MurmurWeb.Artifacts.Registry` and surfaced through `MurmurWeb.Components.Artifacts`:

| Artifact Type | Renderer | Display |
|---------------|----------|---------|
| `papers` | `PaperList` | arXiv search results with title, abstract, links |
| `displayed_paper` | `PdfViewer` | Embedded PDF viewer |
| `sql_results` | `SqlResults` | Paginated query results table |
| `*` | `Generic` | Fallback for unrecognized types |

Artifact-specific follow-up behavior lives in `MurmurWeb.Artifacts.Actions`, which currently handles SQL re-execution without pushing `jido_sql` assumptions down into `jido_murmur_web`.

## Key Modules

| Module | Purpose |
|--------|---------|
| `Murmur.Application` | OTP supervision tree |
| `Murmur.Jido` | Jido framework integration with Ecto storage |
| `Murmur.Repo` | PostgreSQL Ecto repository |
| `MurmurWeb.Endpoint` | Phoenix endpoint with WebSocket |
| `MurmurWeb.Router` | Route definitions |
| `WorkspaceLive` | Multi-agent chat orchestrator |
| `WorkspaceListLive` | Workspace CRUD |
| `MurmurWeb.Live.WorkspaceState` | Workspace-only state projection and persistence helpers |
| `MurmurWeb.Components.Workspace.*` | Demo-owned split/unified workspace presentation modules |

## WorkspaceLive Architecture

The main LiveView handles:
- Agent lifecycle (`add_agent`, `clear_team`, `ensure_agent_started`)
- Message streaming from agents via PubSub subscriptions
- Artifact panel activation and delegation into demo-owned artifact actions
- Task board toggle and creation
- Signal handling: `LLMResponse`, `MessageReceived`, `TaskCreated`, `TaskUpdated`
- Split-view and unified-view chat UI modes

`WorkspaceLive` now delegates:

- Reusable chat and artifact shell rendering to `jido_murmur_web`
- Demo-specific workspace presentation to `MurmurWeb.Components.Workspace.Header`, `SplitView`, and `UnifiedView`
- Artifact-specific rendering and actions to `MurmurWeb.Components.Artifacts`, `MurmurWeb.Artifacts.Registry`, and `MurmurWeb.Artifacts.Actions`
- Non-rendering message and artifact loading logic to `MurmurWeb.Live.WorkspaceState`

## Dependencies

### Umbrella Packages

| Package | Role |
|---------|------|
| `jido_murmur` | Core backend: orchestration, storage, runners |
| `jido_murmur_web` | LiveView components library |
| `jido_tasks` | Task management tools and signals |
| `jido_arxiv` | Academic research search and display |
| `jido_sql` | SQL query execution and display |

### Key External Dependencies

`phoenix ~> 1.8.5`, `phoenix_live_view ~> 1.1.0`, `ecto_sql ~> 3.13`, `postgrex`, `bandit ~> 1.5`, `tailwind ~> 0.3`, `esbuild ~> 0.10`, `mdex ~> 0.4`, `heroicons`

## Configuration

The demo app acts as the configuration hub for all packages:

```elixir
# Jido framework
config :jido, :observability, tracer: JidoMurmur.ObsTracer
config :jido_ai, model_aliases: %{capable: "openai:gpt-5-mini", fast: "openai:gpt-5-mini"}

# Core packages
config :jido_murmur, repo: Murmur.Repo, pubsub: Murmur.PubSub, jido_mod: Murmur.Jido, ...
config :jido_tasks, repo: Murmur.Repo, pubsub: Murmur.PubSub
config :jido_artifacts, pubsub: Murmur.PubSub
config :jido_sql, repo: JidoSql.Repo, max_rows: 50, max_columns: 20

# Phoenix
config :murmur_demo, MurmurWeb.Endpoint, adapter: Bandit.PhoenixAdapter, ...
```
