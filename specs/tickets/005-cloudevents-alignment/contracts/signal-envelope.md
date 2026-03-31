# Contract: Signal Envelope for PubSub

**Scope**: All Murmur ecosystem PubSub broadcasts  
**Standard**: CloudEvents v1.0.2 via Jido.Signal

## PubSub Message Contract

All PubSub broadcasts MUST use this format:

```elixir
Phoenix.PubSub.broadcast(pubsub, topic, %Jido.Signal{
  id: "...",           # UUID7 (auto)
  type: "...",         # Event type string
  source: "...",       # Producer URI
  subject: "...",      # Entity URI (optional)
  time: "...",         # ISO 8601 (auto)
  specversion: "1.0.2",
  data: %{...}        # Event-specific payload
})
```

## Subscriber Pattern

All `handle_info/2` handlers MUST pattern-match on the signal struct:

```elixir
# Match by type
def handle_info(%Jido.Signal{type: "task.created", data: data}, socket) do
  # data.task contains the created task
end

# Match by type prefix (for artifact signals)
def handle_info(%Jido.Signal{type: "artifact." <> _name, data: data}, socket) do
  # data.name, data.data, etc.
end

# Match streaming signals (no more {:agent_signal, ...} wrapper)
def handle_info(%Jido.Signal{type: "ai.llm.delta", data: data}, socket) do
  # data contains delta content
end
```

## Forbidden Patterns

These patterns MUST NOT appear after migration:

```elixir
# FORBIDDEN — raw tuples
Phoenix.PubSub.broadcast(pubsub, topic, {:task_created, task})
Phoenix.PubSub.broadcast(pubsub, topic, {:artifact_update, sid, name, data, mode})
Phoenix.PubSub.broadcast(pubsub, topic, {:agent_signal, sid, signal})

# FORBIDDEN — tuple handlers
def handle_info({:task_created, task}, socket)
def handle_info({:artifact_update, _, _, _, _}, socket)
```

## Signal Type Registry

| Type | Source | Subject | Data Fields |
|------|--------|---------|-------------|
| `artifact.{name}` | `/jido_artifacts/{name}` | `/agents/{agent_id}` | name, data, mode, merge_result?, scope |
| `murmur.message.completed` | `/jido_murmur/runner` | `/workspaces/{wid}/agents/{sid}` | session_id, response |
| `murmur.message.received` | `/jido_murmur/tell_action` | `/workspaces/{wid}/agents/{sid}` | session_id, message |
| `murmur.request.failed` | `/jido_murmur/runner` | `/workspaces/{wid}/agents/{sid}` | session_id, reason |
| `task.created` | `/jido_tasks/tools/add_task` | `/workspaces/{wid}/tasks/{tid}` | task |
| `task.updated` | `/jido_tasks/tools/update_task` | `/workspaces/{wid}/tasks/{tid}` | task |
| `ai.llm.delta` | (jido_ai) | `/agents/{sid}` | content, role |
| `ai.llm.response` | (jido_ai) | `/agents/{sid}` | response |
| `ai.tool.result` | (jido_ai) | `/agents/{sid}` | result |
| `ai.request.started` | (jido_ai) | `/agents/{sid}` | request_id |
| `ai.request.completed` | (jido_ai) | `/agents/{sid}` | request_id |
| `ai.request.failed` | (jido_ai) | `/agents/{sid}` | error |
| `ai.usage` | (jido_ai) | `/agents/{sid}` | tokens, model |
