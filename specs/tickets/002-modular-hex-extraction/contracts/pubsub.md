# PubSub Contracts: Modular Hex Package Extraction

**Feature**: 002-modular-hex-extraction  
**Date**: 2026-03-28  
**Status**: Complete

## Overview

All PubSub messages are broadcast via `Phoenix.PubSub` using the consumer-configured PubSub module (`JidoMurmur.pubsub()`). Messages carry native Jido types wherever applicable — `Jido.Signal` structs, `Jido.Signal.ID` identifiers — to preserve full signal information for consumer-side pattern matching.

## Topic Contracts

### Workspace Messages

**Topic**: `"workspace:#{workspace_id}"`  
**Package**: `jido_murmur`  
**Producer**: `JidoMurmur.Runner`, `JidoMurmur.TellAction`

| Message | Shape | Description |
|---------|-------|-------------|
| `{:new_message, session_id, msg}` | `session_id :: binary_id, msg :: map` | New user or inter-agent message. `msg.id` is a `Jido.Signal.ID`. `msg` contains `:content`, `:sender_name`, `:id` |
| `{:agent_added, session}` | `session :: JidoMurmur.Workspaces.AgentSession.t()` | Agent session created in workspace |
| `{:agent_removed, session}` | `session :: JidoMurmur.Workspaces.AgentSession.t()` | Agent session removed from workspace |

**Consumer usage**:
```elixir
Phoenix.PubSub.subscribe(MyApp.PubSub, "workspace:#{workspace_id}")

def handle_info({:new_message, session_id, msg}, socket) do
  # msg.id is a Jido.Signal.ID — standard Jido type
  # ...
end
```

---

### Agent Streaming Signals

**Topic**: `"agent_stream:#{session_id}"`  
**Package**: `jido_murmur`  
**Producer**: `JidoMurmur.StreamingPlugin`

| Message | Shape | Description |
|---------|-------|-------------|
| `{:agent_signal, session_id, signal}` | `signal :: Jido.Signal.t()` | Native Jido signal struct. Consumers pattern-match on `signal.type` |

**Signal types forwarded**:

| Signal Type | When Emitted | Key Data |
|-------------|--------------|----------|
| `"ai.llm.delta"` | LLM streaming token | `signal.data.content` — partial text |
| `"ai.llm.response"` | LLM response complete | `signal.data` — full response |
| `"ai.tool.result"` | Tool execution finished | `signal.data` — tool result |
| `"ai.request.start"` | ReAct loop iteration start | `signal.data` — request metadata |
| `"ai.request.end"` | ReAct loop iteration end | `signal.data` — request summary |
| `"ai.usage"` | Token usage report | `signal.data` — usage counts |

**Consumer usage**:
```elixir
Phoenix.PubSub.subscribe(MyApp.PubSub, JidoMurmur.StreamingPlugin.stream_topic(session_id))

def handle_info({:agent_signal, _session_id, %Jido.Signal{type: "ai.llm.delta"} = signal}, socket) do
  # Direct Jido signal pattern matching — no wrapper types
  append_delta(signal.data.content)
end
```

---

### Artifact Updates

**Topic**: `"agent_artifacts:#{session_id}"`  
**Package**: `jido_murmur`  
**Producer**: `JidoMurmur.ArtifactPlugin`

| Message | Shape | Description |
|---------|-------|-------------|
| `{:artifact_update, session_id, name, data, mode}` | `name :: String.t(), data :: term(), mode :: :replace \| :append` | Artifact content update. Originated from `Jido.Agent.Directive.Emit` |

**Consumer usage**:
```elixir
Phoenix.PubSub.subscribe(MyApp.PubSub, JidoMurmur.Artifact.artifact_topic(session_id))

def handle_info({:artifact_update, _session_id, name, data, mode}, socket) do
  # mode is :replace or :append
  update_artifact(name, data, mode)
end
```

---

### Task Updates

**Topic**: `"workspace:#{workspace_id}:tasks"`  
**Package**: `jido_tasks`  
**Producer**: `JidoTasks.Tasks` context, `JidoTasks.Tools.*`

| Message | Shape | Description |
|---------|-------|-------------|
| `{:task_created, task}` | `task :: JidoTasks.Task.t()` | New task created |
| `{:task_updated, task}` | `task :: JidoTasks.Task.t()` | Task status/content changed |

**Consumer usage**:
```elixir
Phoenix.PubSub.subscribe(MyApp.PubSub, JidoTasks.Tasks.tasks_topic(workspace_id))

def handle_info({:task_created, task}, socket) do
  # task is a standard Ecto struct
end
```

---

## Topic Helper Functions

Each package provides helper functions for constructing topic strings:

| Function | Returns | Package |
|----------|---------|---------|
| `JidoMurmur.StreamingPlugin.stream_topic(session_id)` | `"agent_stream:#{session_id}"` | `jido_murmur` |
| `JidoMurmur.Artifact.artifact_topic(session_id)` | `"agent_artifacts:#{session_id}"` | `jido_murmur` |
| `JidoTasks.Tasks.tasks_topic(workspace_id)` | `"workspace:#{workspace_id}:tasks"` | `jido_tasks` |

Workspace topic (`"workspace:#{workspace_id}"`) is constructed directly by consumers or via `JidoMurmur.AgentHelper` convenience functions.

---

## Stability Guarantees

- Topic format strings are part of the public API and follow semver
- Message tuple shapes (tag + arity) are stable within a major version
- `Jido.Signal` struct internals follow Jido's own semver — `jido_murmur` does not modify signals
- New message types may be added in minor versions (additive, non-breaking)
- Existing message types will not change shape within a major version
