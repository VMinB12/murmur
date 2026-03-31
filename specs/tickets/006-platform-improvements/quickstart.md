# Quickstart: Platform Infrastructure Improvements

**Feature Branch**: `006-platform-improvements`

## What Changed

1. **Centralized PubSub topics** — All topics now use `JidoMurmur.Topics` helpers
2. **Workspace context in plugins** — Artifact and streaming plugins broadcast to workspace-scoped topics  
3. **Startup config validation** — Missing config produces clear error messages
4. **Task telemetry** — jido_tasks emits `:telemetry` events for observability
5. **Agent profile behaviour** — Compile-time enforcement for profile modules

## PubSub Topic Migration

### Before (inline strings)
```elixir
topic = "agent_artifacts:#{session_id}"
Phoenix.PubSub.subscribe(pubsub, "workspace:#{wid}:agent:#{sid}")
```

### After (centralized helpers)
```elixir
alias JidoMurmur.Topics

topic = Topics.agent_artifacts(workspace_id, session_id)
Phoenix.PubSub.subscribe(pubsub, Topics.agent_messages(workspace_id, session_id))
```

## Config Validation

Missing config now produces actionable errors at startup:

```
** (RuntimeError) Missing required configuration for :jido_murmur

  The following keys are not configured:
    - :pubsub

  Add to your config/config.exs:
    config :jido_murmur, pubsub: MyApp.PubSub
```

## Task Telemetry

Attach a handler to observe task operations:

```elixir
:telemetry.attach("task-logger", [:jido_tasks, :task, :create, :stop], fn _name, measurements, metadata, _config ->
  Logger.info("Task #{metadata.task_id} created in #{measurements.duration}ns")
end, nil)
```

## Agent Profile Behaviour

Add to your profile modules for compile-time validation:

```elixir
defmodule MyApp.Agents.Profiles.ResearchAgent do
  @behaviour JidoMurmur.AgentProfile  # ← compile-time callback checking

  use Jido.AI.Agent,
    name: "research_agent",
    # ... options
end
```
