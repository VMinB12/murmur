# JidoMurmur

Multi-agent orchestration for [Jido](https://github.com/agentjido/jido). Provides Runner, Plugins, Storage, Schemas, and convenience helpers for building multi-agent chat applications.

## Installation

Add `jido_murmur` to your dependencies:

```elixir
def deps do
  [{:jido_murmur, "~> 0.1.0"}]
end
```

Run the migration generator:

```bash
mix jido_murmur.install
mix ecto.migrate
```

## Configuration

```elixir
config :jido_murmur,
  repo: MyApp.Repo,
  pubsub: MyApp.PubSub,
  jido_mod: MyApp.Jido,
  otp_app: :my_app,
  profiles: [MyApp.Agents.AssistantAgent]
```

Add `JidoMurmur.Supervisor` to your application supervision tree:

```elixir
children = [
  MyApp.Repo,
  {Phoenix.PubSub, name: MyApp.PubSub},
  MyApp.Jido,
  {JidoMurmur.Supervisor, []}
]
```

## Jido Interplay

JidoMurmur is designed as a Jido-native library. All public APIs return standard Jido types (pids, `Jido.Signal` structs, `Jido.Thread` entries). You can use Jido APIs directly alongside JidoMurmur without any conflicts.

### Using Jido APIs Directly

Agents started via `AgentHelper.start_agent/1` are standard Jido agent processes. You can interact with them using Jido APIs:

```elixir
# Start agent via JidoMurmur helper
{:ok, pid} = JidoMurmur.AgentHelper.start_agent(session)

# Access state directly via Jido
{:ok, %{agent: agent, status: status}} = Jido.AgentServer.state(pid)

# Lookup via the Jido registry
pid = MyApp.Jido.whereis(session.id)
```

### Custom Plugins Alongside Package Plugins

Define your own `Jido.Plugin` and add it to agent profiles alongside JidoMurmur plugins:

```elixir
defmodule MyApp.AuditPlugin do
  use Jido.Plugin,
    name: "audit",
    state_key: :audit,
    actions: [],
    signal_patterns: ["ai.llm.response"]

  @impl Jido.Plugin
  def handle_signal(signal, context) do
    MyApp.AuditLog.record(context.agent.id, signal)
    {:ok, :continue}
  end
end

defmodule MyApp.Agents.AssistantAgent do
  use Jido.AI.Agent,
    name: "assistant",
    description: "General assistant",
    model: :fast,
    tools: [],
    plugins: [
      JidoMurmur.StreamingPlugin,
      JidoMurmur.ArtifactPlugin,
      MyApp.AuditPlugin
    ],
    system_prompt: "You are a helpful assistant."

  def catalog_meta, do: %{color: "blue"}
end
```

All plugins receive signals in declaration order. Custom plugins do not interfere with package plugins.

### Alternative Storage Backends

JidoMurmur ships with `JidoMurmur.Storage.Ecto` but works with any `Jido.Storage` implementation. Configure your `use Jido` module with the adapter of your choice:

```elixir
# ETS storage (development/testing)
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app, storage: {Jido.Storage.ETS, [table: :my_storage]}
end

# Redis storage
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app, storage: {Jido.Storage.Redis, [url: "redis://localhost"]}
end
```

The Runner, AgentHelper, and all other JidoMurmur components work transparently with any storage backend.

### Composing Package and Custom Actions

Add JidoMurmur actions to your agent's tool list alongside custom actions:

```elixir
defmodule MyApp.Agents.TeamAgent do
  use Jido.AI.Agent,
    name: "team_agent",
    tools: [
      JidoMurmur.TellAction,          # Package action: inter-agent messaging
      MyApp.Actions.SearchKnowledge,   # Custom action
      MyApp.Actions.CreateTicket       # Custom action
    ],
    plugins: [JidoMurmur.StreamingPlugin, JidoMurmur.ArtifactPlugin],
    system_prompt: "You are a team collaboration agent."

  def catalog_meta, do: %{color: "violet"}
end
```

## API Reference

### Core Modules

| Module | Purpose |
|--------|---------|
| `JidoMurmur.Runner` | Ask/await drain-loop orchestration |
| `JidoMurmur.AgentHelper` | Convenience functions (start, load, subscribe) |
| `JidoMurmur.Catalog` | Config-driven agent profile registry |
| `JidoMurmur.Workspaces` | Workspace and session CRUD |
| `JidoMurmur.Storage.Ecto` | PostgreSQL storage adapter (`Jido.Storage` impl) |

### Plugins

| Module | Purpose |
|--------|---------|
| `JidoMurmur.StreamingPlugin` | Forwards LLM signals to PubSub |
| `JidoMurmur.ArtifactPlugin` | Handles artifact signals and persistence |

### Actions

| Module | Purpose |
|--------|---------|
| `JidoMurmur.TellAction` | Inter-agent fire-and-forget messaging |
| `JidoMurmur.Actions.StoreArtifact` | Artifact state persistence |

## License

See LICENSE file.
