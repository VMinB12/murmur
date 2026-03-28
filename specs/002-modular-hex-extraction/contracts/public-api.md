# Public API Contracts: Modular Hex Package Extraction

**Feature**: 002-modular-hex-extraction  
**Date**: 2026-03-28  
**Status**: Complete

## Overview

This document defines the public API surface for each package. APIs follow the Jido-native principle: all return types are standard Elixir/Jido types (pids, Signal structs, Ecto structs). No wrapper types are introduced.

---

## Package: `jido_murmur`

### Configuration API (`JidoMurmur`)

```elixir
# Accessors — read from application environment
JidoMurmur.repo()       :: module()    # Consumer's Ecto.Repo
JidoMurmur.pubsub()     :: module()    # Consumer's Phoenix.PubSub
JidoMurmur.jido_mod()   :: module()    # Consumer's `use Jido` module
JidoMurmur.otp_app()    :: atom()      # Consumer's OTP app name
```

### Runner API (`JidoMurmur.Runner`)

```elixir
# Send a message to an agent session. Queues if agent is busy.
Runner.send_message(session :: AgentSession.t(), content :: String.t())
  :: :queued | :agent_not_running

# Check if an agent session has a drain-loop running
Runner.active?(session_id :: binary_id()) :: boolean()
```

### Agent Helper API (`JidoMurmur.AgentHelper`)

Convenience functions that return Jido-native types. Consumers can always bypass these and call Jido directly.

```elixir
# Start an agent process for a session, return Jido pid
AgentHelper.start_agent(session :: AgentSession.t())
  :: {:ok, pid()} | {:error, term()}

# Load messages from storage, return Jido thread entries
AgentHelper.load_messages(session :: AgentSession.t())
  :: [map()]  # UITurn-projected messages

# Load artifacts from agent state
AgentHelper.load_artifacts(session :: AgentSession.t())
  :: map()  # %{artifact_name => artifact_data}

# Subscribe to all PubSub topics for a session
AgentHelper.subscribe(session :: AgentSession.t())
  :: :ok

# Subscribe to all PubSub topics for a workspace
AgentHelper.subscribe_workspace(workspace_id :: binary_id())
  :: :ok

# Clean up storage for a workspace (delete threads, checkpoints)
AgentHelper.cleanup_workspace_storage(workspace_id :: binary_id())
  :: :ok
```

### Workspace Context API (`JidoMurmur.Workspaces`)

```elixir
Workspaces.create_workspace(attrs :: map())
  :: {:ok, Workspace.t()} | {:error, Ecto.Changeset.t()}

Workspaces.get_workspace!(id :: binary_id(), scope :: map())
  :: Workspace.t()  # raises Ecto.NoResultsError

Workspaces.list_workspaces()
  :: [Workspace.t()]

Workspaces.list_agent_sessions(workspace_id :: binary_id())
  :: [AgentSession.t()]

Workspaces.create_agent_session(workspace_id :: binary_id(), attrs :: map())
  :: {:ok, AgentSession.t()} | {:error, Ecto.Changeset.t()}

Workspaces.delete_agent_session(session :: AgentSession.t())
  :: {:ok, AgentSession.t()} | {:error, Ecto.Changeset.t()}

Workspaces.get_agent_session!(id :: binary_id())
  :: AgentSession.t()

Workspaces.find_agent_session_by_name(workspace_id :: binary_id(), display_name :: String.t())
  :: AgentSession.t() | nil
```

**Note**: The `@max_agents_per_workspace` limit is removed (FR-015). Consumers enforce their own limits.

### Catalog API (`JidoMurmur.Catalog`)

```elixir
# List all registered agent profiles (from config)
Catalog.list_profiles()
  :: [%{id: String.t(), description: String.t(), color: String.t()}]

# Get a specific profile by ID
Catalog.get_profile!(id :: String.t())
  :: %{id: String.t(), agent_module: module(), description: String.t(), color: String.t()}

# Get the agent module for a profile
Catalog.agent_module(profile_id :: String.t())
  :: module()

# Get Tailwind color classes for an agent
Catalog.agent_color(profile_id :: String.t(), agent_name :: String.t())
  :: String.t()
```

### UITurn API (`JidoMurmur.UITurn`)

```elixir
# Project Jido thread entries into display-ready message maps
UITurn.project_entries(entries :: [map()])
  :: [map()]  # List of UITurn structs with :id, :thinking, :tool_calls, :content, :sender_name, :status
```

### Storage API (`JidoMurmur.Storage.Ecto`)

Implements `Jido.Storage` behaviour — consumers configure this in their `use Jido` call:

```elixir
# All callbacks from Jido.Storage:
Storage.Ecto.get_checkpoint(key, opts)     :: {:ok, map()} | {:error, :not_found}
Storage.Ecto.put_checkpoint(key, data, opts)  :: :ok | {:error, term()}
Storage.Ecto.delete_checkpoint(key, opts)  :: :ok
Storage.Ecto.load_thread(thread_id, opts)  :: {:ok, [map()]}
Storage.Ecto.append_thread(thread_id, entries, opts)  :: :ok | {:error, term()}
Storage.Ecto.delete_thread(thread_id, opts)  :: :ok
```

### LLM Adapter Behaviour (`JidoMurmur.LLM`)

```elixir
@callback ask(module(), pid(), String.t(), map()) :: {:ok, handle()} | {:error, term()}
@callback await(module(), handle(), keyword()) :: {:ok, term()} | {:error, term()}
```

**Implementations**:
- `JidoMurmur.LLM.Real` — production adapter (calls Jido agent)
- `JidoMurmur.LLM.Mock` — test adapter with configurable responses (FR-021)

### Supervisor API (`JidoMurmur.Supervisor`)

```elixir
# Consumers add to their supervision tree:
{JidoMurmur.Supervisor, []}
```

Manages: `JidoMurmur.TableOwner` (ETS tables)

### Plugin APIs (Jido-Native)

These all implement `Jido.Plugin` — consumers add them to agent `plugins:` lists:

```elixir
# StreamingPlugin — broadcasts signals to PubSub
JidoMurmur.StreamingPlugin  # use Jido.Plugin, name: "streaming"
JidoMurmur.StreamingPlugin.stream_topic(session_id)  :: String.t()

# ArtifactPlugin — handles artifact signals, routes to StoreArtifact
JidoMurmur.ArtifactPlugin  # use Jido.Plugin, name: "artifacts"
```

### Action APIs (Jido-Native)

These all implement `Jido.Action` — consumers add them to agent `tools:` lists:

```elixir
# TellAction — inter-agent fire-and-forget messaging
JidoMurmur.TellAction  # use Jido.Action, name: "tell"
# schema: target_agent :: string (required), message :: string (required)

# StoreArtifact — artifact state persistence (used internally by ArtifactPlugin)
JidoMurmur.Actions.StoreArtifact  # use Jido.Action
```

### Request Transformer APIs (Jido-Native)

```elixir
# MessageInjector — injects team context + pending messages
JidoMurmur.MessageInjector
# implements Jido.AI.Reasoning.ReAct.RequestTransformer

# ComposableRequestTransformer — chains multiple transformers (FR-007)
JidoMurmur.ComposableRequestTransformer
# implements Jido.AI.Reasoning.ReAct.RequestTransformer
# config: transformers: [module(), ...]
```

---

## Package: `jido_murmur_web`

### Component API

All components are `Phoenix.Component` function components:

```elixir
# Import for direct use:
import JidoMurmurWeb.Components

# Available components:
<JidoMurmurWeb.Components.ChatMessage.chat_message message={msg} color={color} />
<JidoMurmurWeb.Components.ChatStream.chat_stream messages={@streams.messages} />
<JidoMurmurWeb.Components.AgentHeader.agent_header session={session} color={color} />
<JidoMurmurWeb.Components.MessageInput.message_input form={@form} />
<JidoMurmurWeb.Components.StreamingIndicator.streaming_indicator signals={signals} />
<JidoMurmurWeb.Components.AgentSelector.agent_selector profiles={profiles} />
<JidoMurmurWeb.Components.WorkspaceList.workspace_list workspaces={@streams.workspaces} />
<JidoMurmurWeb.Components.ArtifactPanel.artifact_panel artifacts={artifacts} renderers={renderers} />
```

### Generator API (Mix Tasks)

```elixir
# Install component group into consumer project
mix jido_murmur_web.install chat       # ChatMessage, ChatStream, MessageInput, StreamingIndicator
mix jido_murmur_web.install workspace  # WorkspaceList, AgentSelector, AgentHeader
mix jido_murmur_web.install artifacts  # ArtifactPanel
mix jido_murmur_web.install all        # All components
```

---

## Package: `jido_tasks`

### Task Context API (`JidoTasks.Tasks`)

```elixir
Tasks.list_tasks(workspace_id :: binary_id(), opts :: keyword())
  :: [Task.t()]
  # opts: [status: :todo | :in_progress | :done | :aborted]

Tasks.get_task!(id :: binary_id())
  :: Task.t()

Tasks.get_task(id :: binary_id())
  :: Task.t() | nil

Tasks.create_task(workspace_id :: binary_id(), attrs :: map(), created_by :: String.t())
  :: {:ok, Task.t()} | {:error, Ecto.Changeset.t()}

Tasks.update_task(task :: Task.t(), attrs :: map())
  :: {:ok, Task.t()} | {:error, Ecto.Changeset.t()}

Tasks.task_stats(workspace_id :: binary_id())
  :: %{atom() => non_neg_integer()}

Tasks.delete_tasks_for_workspace(workspace_id :: binary_id())
  :: {non_neg_integer(), nil}

Tasks.tasks_topic(workspace_id :: binary_id())
  :: String.t()  # "workspace:#{workspace_id}:tasks"
```

### Tool Actions (Jido-Native)

```elixir
# AddTask — create a task in the workspace
JidoTasks.Tools.AddTask  # use Jido.Action, name: "add_task"
# schema: title :: string (required), description :: string, assignee :: string (required)

# UpdateTask — update a task's status
JidoTasks.Tools.UpdateTask  # use Jido.Action, name: "update_task"
# schema: task_id :: string (required), status :: string, title :: string, description :: string

# ListTasks — list workspace tasks
JidoTasks.Tools.ListTasks  # use Jido.Action, name: "list_tasks"
# schema: status :: string (optional filter)
```

### Generator API

```elixir
mix jido_tasks.install  # Creates migration for jido_tasks table
```

---

## Package: `jido_arxiv`

### Tool Actions (Jido-Native)

```elixir
# ArxivSearch — search arXiv API and emit paper artifact
JidoArxiv.Tools.ArxivSearch  # use Jido.Action, name: "arxiv_search"
# schema: query :: string (required)
# Returns: LLM-friendly summary text + emits "papers" artifact via Jido.Agent.Directive.Emit

# DisplayPaper — display a specific paper as artifact
JidoArxiv.Tools.DisplayPaper  # use Jido.Action, name: "display_paper"
# schema: paper_id :: string (required)
```

---

## Dependency Graph

```
jido_arxiv ──→ jido_murmur ──→ jido, jido_ai, jido_signal, jido_action
                               phoenix_pubsub, phoenix_ecto, ecto_sql, postgrex
                               req_llm, jason

jido_tasks ──→ jido_murmur ──→ (same as above)
               jido_action, ecto_sql

jido_murmur_web ──→ jido_murmur
                    phoenix, phoenix_live_view, phoenix_html

murmur_demo ──→ jido_murmur (in_umbrella)
               jido_murmur_web (in_umbrella)
               jido_tasks (in_umbrella)
               jido_arxiv (in_umbrella)
               + phoenix, bandit, telemetry, esbuild, tailwind, heroicons, etc.
```

---

## Versioning

All packages start at `0.1.0` to signal API instability during early development.

Semver rules:
- `0.x.y` — breaking changes allowed in minor bumps
- `1.0.0` — stable public API; breaking changes only in major bumps
- Inter-package version constraints use `~> 0.1` (pessimistic minor)
