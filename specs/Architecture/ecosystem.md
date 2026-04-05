# Ecosystem — Package Composition Guide

How the Murmur umbrella packages are designed to work together in a full application.

## Package Dependency Graph

```
                    ┌─────────────────┐
                    │   murmur_demo   │  ← Reference application
                    │  (Phoenix app)  │
                    └───┬──┬──┬──┬──┬─┘
                        │  │  │  │  │
          ┌─────────────┘  │  │  │  └─────────────┐
          ↓                │  │  │                ↓
  ┌───────────────┐        │  │  │        ┌───────────────┐
  │jido_murmur_web│        │  │  │        │   jido_sql    │
  │ (LiveView UI) │        │  │  │        │ (SQL plugin)  │
  └───────┬───────┘        │  │  │        └───────┬───────┘
          │                │  │  │                │
          ↓                ↓  │  ↓                ↓
  ┌───────────────┐  ┌────────┴───────┐  ┌───────────────┐
  │  jido_murmur  │←─│  jido_tasks    │  │  jido_arxiv   │
  │   (core)      │  │  (task mgmt)   │  │ (arXiv tools) │
  └───────┬───────┘  └────────────────┘  └───────┬───────┘
          │                                      │
          └──────────────┬───────────────────────┘
                         ↓
                 ┌───────────────┐
                 │jido_artifacts │
                 │  (artifacts)  │
                 └───────┬───────┘
                         ↓
              ┌──────────────────────┐
              │   Jido Framework     │
              │ (jido, jido_ai,      │
              │  jido_action,        │
              │  jido_signal)        │
              └──────────────────────┘
```

## Minimum Viable Integration

The simplest possible integration requires only `jido_murmur` and a Phoenix application:

```elixir
# mix.exs
{:jido_murmur, "~> 0.1"}
```

```elixir
# config.exs
config :jido_murmur,
  repo: MyApp.Repo,
  pubsub: MyApp.PubSub,
  jido_mod: MyApp.Jido,
  otp_app: :my_app,
  profiles: [MyApp.Agents.MyAgent]
```

This gives you: workspaces, agent sessions, ingress-coordinated delivery, single-run execution, inter-agent messaging (TellAction), conversation persistence, and PubSub streaming.

## Adding Capabilities

Each additional package adds a capability layer. All are optional and independent of each other.

### Adding UI Components

```elixir
{:jido_murmur_web, "~> 0.1"}
```

Provides drop-in LiveView components for chat messages, streaming indicators, agent management, and artifact panels. Import directly or copy via `mix jido_murmur_web.install` for full customization.

**Requires:** Tailwind source directive in `app.css`:
```css
@source "../../../deps/jido_murmur_web";
```

### Adding Artifacts

```elixir
{:jido_artifacts, "~> 0.1"}
```

Enables agents to emit rich artifacts (HTML, charts, data tables) that persist in agent state and broadcast to the UI. Register `ArtifactPlugin` in agent profiles.

**Requires:** PubSub configuration:
```elixir
config :jido_artifacts, pubsub: MyApp.PubSub
```

### Adding Task Management

```elixir
{:jido_tasks, "~> 0.1"}
```

Workspace-scoped task boards with agent tools (`AddTask`, `UpdateTask`, `ListTasks`). Run `mix jido_tasks.install` for migrations and config.

**Requires:** Repo and PubSub configuration. Include task tools in agent profiles.

### Adding arXiv Research

```elixir
{:jido_arxiv, "~> 0.1"}
```

Agent tools for arXiv search and paper display. Stateless — no database or config required. Uses `jido_artifacts` for paper/PDF artifact emission.

### Adding SQL Query

```elixir
{:jido_sql, "~> 0.1"}
```

Natural-language-to-SQL with safety guardrails. Requires a separate database connection via `SQL_AGENT_DATABASE_URL`. Includes schema introspection cached at startup.

## Shared Infrastructure

All packages share three infrastructure concerns provided by the host application:

| Concern | Module | Used By |
|---------|--------|---------|
| Database | `MyApp.Repo` (Ecto) | `jido_murmur`, `jido_tasks` |
| PubSub | `MyApp.PubSub` (Phoenix) | `jido_murmur`, `jido_tasks`, `jido_artifacts` |
| Agent Runtime | `MyApp.Jido` (Jido) | `jido_murmur` |

The host app provides these in its supervision tree:

```elixir
children = [
  MyApp.Repo,
  {Phoenix.PubSub, name: MyApp.PubSub},
  MyApp.Jido,
  {JidoMurmur.Supervisor, []}
]
```

## Agent Profile Composition

Agent profiles are the composition point where packages combine. A profile declares which tools, plugins, and transformers an agent uses:

```elixir
use Jido.AI.Agent,
  name: "my_agent",
  model: :fast,
  tools: [
    JidoMurmur.TellAction,           # from jido_murmur (inter-agent messaging)
    JidoTasks.Tools.AddTask,          # from jido_tasks
    JidoTasks.Tools.UpdateTask,       # from jido_tasks
    JidoTasks.Tools.ListTasks,        # from jido_tasks
    JidoArxiv.Tools.ArxivSearch,      # from jido_arxiv
    JidoArxiv.Tools.DisplayPaper,     # from jido_arxiv
    JidoSql.Tools.Query,              # from jido_sql
    JidoSql.Tools.Display             # from jido_sql
  ],
  plugins: [
    JidoMurmur.StreamingPlugin,       # from jido_murmur
    JidoArtifacts.ArtifactPlugin      # from jido_artifacts
  ],
  request_transformer: JidoSql.RequestTransformer  # from jido_sql (optional)
```

Not every agent needs every tool. The reference profiles in `murmur_demo` show three different compositions:
- **GeneralAgent:** TellAction + task tools only
- **ArxivAgent:** TellAction + arXiv tools + task tools
- **SqlAgent:** TellAction + SQL tools + task tools + schema transformer

## PubSub Topic Convention

All packages follow a consistent topic hierarchy for real-time events:

```
workspace:{workspace_id}                      # workspace-level events
workspace:{workspace_id}:agent:{session_id}:messages   # inter-agent messages
workspace:{workspace_id}:agent:{session_id}:stream     # LLM streaming events
workspace:{workspace_id}:agent:{session_id}:artifacts   # artifact updates
workspace:{workspace_id}:tasks                          # task board events
```

The LiveView subscribes to all relevant topics when an agent session starts via `JidoMurmur.AgentHelper.subscribe/1`.

## Signal Flow

Packages communicate through Jido signals broadcast on PubSub:

```
Agent tool execution
    ↓
Jido.Signal emitted (e.g., "artifact.papers", "task.created")
    ↓
Plugin pipeline processes signal
    ↓
StreamingPlugin broadcasts to PubSub topic
    ├── LiveView receives via handle_info/2 → updates UI
    └── ArtifactPlugin stores in agent state → persisted
```

## Observability Integration

The `ObsTracer` in `jido_murmur` enriches all OpenTelemetry spans with workspace and agent identity. This works transparently across all packages because tracing is configured at the Jido framework level:

```elixir
config :jido, :observability, tracer: JidoMurmur.ObsTracer
```

Any LLM call, tool execution, or signal processing from any package automatically gets workspace-scoped tracing.

## Creating a New Tool Package

To create a new tool package that integrates with the ecosystem:

1. Create a new umbrella app: `mix new apps/jido_my_tool --sup`
2. Add `jido_action ~> 2.0` as a dependency
3. Implement tools as `Jido.Action` modules with `run/2` callbacks
4. If emitting artifacts, depend on `jido_artifacts` and use `Artifact.emit/4`
5. If needing database, accept `repo` config like `jido_tasks` does
6. Register tools in agent profiles
7. Optionally add a `mix jido_my_tool.install` task with Igniter
