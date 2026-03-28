# Quickstart: jido_murmur Consumer Integration

**Feature**: 002-modular-hex-extraction  
**Date**: 2026-03-28  
**Status**: Complete

## Prerequisites

- Elixir >= 1.15 / OTP
- Phoenix 1.8+ application with Ecto/PostgreSQL
- Familiarity with Jido 2.0 framework

---

## Step 1: Add Dependencies

```elixir
# mix.exs
defp deps do
  [
    {:jido_murmur, "~> 0.1"},
    # Optional — pick what you need:
    {:jido_murmur_web, "~> 0.1"},  # LiveView components
    {:jido_tasks, "~> 0.1"},        # Task management tools
    {:jido_arxiv, "~> 0.1"},        # arXiv research tools
  ]
end
```

## Step 2: Configure

```elixir
# config/config.exs
config :jido_murmur,
  repo: MyApp.Repo,
  pubsub: MyApp.PubSub,
  jido_mod: MyApp.Jido,
  otp_app: :my_app,
  profiles: [
    MyApp.Agents.AssistantAgent,
    # Add more agent profile modules here
  ]

# If using jido_tasks:
config :jido_tasks,
  repo: MyApp.Repo,
  pubsub: MyApp.PubSub
```

## Step 3: Install Migrations

```bash
mix jido_murmur.install    # Creates workspace, session, checkpoint, thread_entry migrations
mix jido_tasks.install     # Creates tasks migration (optional)
mix ecto.migrate
```

## Step 4: Create Your Jido Bootstrap Module

```elixir
# lib/my_app/jido.ex
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app, storage: {JidoMurmur.Storage.Ecto, []}
end
```

## Step 5: Add to Supervision Tree

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    MyApp.Repo,
    {Phoenix.PubSub, name: MyApp.PubSub},
    {JidoMurmur.Supervisor, []},     # ETS tables, package processes
    MyAppWeb.Endpoint,
    MyApp.Jido                        # Jido agent supervisor
  ]

  Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
end
```

## Step 6: Define an Agent Profile

```elixir
# lib/my_app/agents/assistant_agent.ex
defmodule MyApp.Agents.AssistantAgent do
  use Jido.AI.Agent,
    name: "assistant",
    description: "A helpful multi-purpose assistant",
    model: :fast,
    tools: [JidoMurmur.TellAction],
    plugins: [JidoMurmur.StreamingPlugin, JidoMurmur.ArtifactPlugin],
    request_transformer: JidoMurmur.MessageInjector,
    system_prompt: "You are a helpful assistant."

  def catalog_meta, do: %{color: "blue"}
end
```

## Step 7: Use in a LiveView

```elixir
defmodule MyAppWeb.ChatLive do
  use MyAppWeb, :live_view

  alias JidoMurmur.{AgentHelper, Runner, Workspaces, Catalog}

  def mount(%{"id" => workspace_id}, _session, socket) do
    workspace = Workspaces.get_workspace!(workspace_id)
    sessions = Workspaces.list_agent_sessions(workspace_id)

    # Subscribe to workspace and all session topics
    AgentHelper.subscribe_workspace(workspace_id)
    for session <- sessions do
      AgentHelper.subscribe(session)
      AgentHelper.start_agent(session)
    end

    # Load message history from Jido storage
    messages = for session <- sessions do
      AgentHelper.load_messages(session)
    end |> List.flatten()

    {:ok,
     socket
     |> assign(workspace: workspace, sessions: sessions)
     |> stream(:messages, messages)}
  end

  def handle_event("send_message", %{"content" => content}, socket) do
    session = hd(socket.assigns.sessions)
    Runner.send_message(session, content)
    {:noreply, socket}
  end

  # Handle streaming signals — these are native Jido.Signal structs
  def handle_info({:agent_signal, _session_id, signal}, socket) do
    # Pattern match on signal.type for different handling
    {:noreply, socket}
  end

  def handle_info({:new_message, _session_id, msg}, socket) do
    {:noreply, stream_insert(socket, :messages, msg)}
  end
end
```

---

## Optional: Add Task Tools to an Agent

```elixir
defmodule MyApp.Agents.ProjectManager do
  use Jido.AI.Agent,
    name: "project_manager",
    description: "Manages project tasks and coordination",
    model: :capable,
    tools: [
      JidoMurmur.TellAction,
      JidoTasks.Tools.AddTask,
      JidoTasks.Tools.UpdateTask,
      JidoTasks.Tools.ListTasks,
    ],
    plugins: [JidoMurmur.StreamingPlugin, JidoMurmur.ArtifactPlugin],
    request_transformer: JidoMurmur.MessageInjector,
    system_prompt: "You are a project manager. Use task tools to track work."

  def catalog_meta, do: %{color: "green"}
end
```

## Optional: Use LiveView Components (Direct Import)

```elixir
# In your LiveView template
import JidoMurmurWeb.Components.ChatMessage
import JidoMurmurWeb.Components.StreamingIndicator

# In app.css — add source directive for package components
# @source "../../../deps/jido_murmur_web";
```

Or copy components into your project for full customization:
```bash
mix jido_murmur_web.install chat
```

## Optional: Custom Request Transformer Composition

```elixir
defmodule MyApp.AuditTransformer do
  @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

  def transform_request(request, state, config, runtime_context) do
    # Add audit context to messages
    {:ok, %{request | messages: request.messages ++ [audit_message()]}}
  end
end

# In agent definition:
use Jido.AI.Agent,
  request_transformer: {JidoMurmur.ComposableRequestTransformer,
    transformers: [JidoMurmur.MessageInjector, MyApp.AuditTransformer]}
```

## Optional: Pluggable Authorization (Add Later)

```elixir
# Step 1: Implement authorize module
defmodule MyApp.JidoAuthorize do
  def authorize(:read, %{owner_id: owner_id}, %{user_id: user_id})
      when not is_nil(owner_id) and owner_id != user_id,
      do: {:error, :unauthorized}

  def authorize(_action, _resource, _scope), do: :ok
end

# Step 2: Configure
config :jido_murmur,
  authorize: MyApp.JidoAuthorize

# Step 3: Data migration — populate owner_id on existing records
# (Schema already has nullable owner_id — no schema change needed)
```
