# Quickstart: CloudEvents Signal Alignment

**Feature Branch**: `005-cloudevents-alignment`

## What Changed

All PubSub messages are now proper `%Jido.Signal{}` structs following the CloudEvents v1.0.2 standard. No more raw tuples. Every signal carries `type`, `source`, `subject`, `id`, and `time` fields.

## For LiveView Developers

### Before (raw tuples)
```elixir
def handle_info({:task_created, task}, socket) do
  # ...
end

def handle_info({:artifact_update, _sid, name, data, _mode}, socket) do
  # ...
end

def handle_info({:agent_signal, _sid, %{type: "ai.llm.delta", data: data}}, socket) do
  # ...
end
```

### After (signal envelopes)
```elixir
def handle_info(%Jido.Signal{type: "task.created", data: %{task: task}}, socket) do
  # ...
end

def handle_info(%Jido.Signal{type: "artifact." <> _name, data: data}, socket) do
  # data.name, data.data available
end

def handle_info(%Jido.Signal{type: "ai.llm.delta", data: data}, socket) do
  # No more {:agent_signal, ...} wrapper
end
```

### Key differences:
1. Pattern match on `%Jido.Signal{type: "...", data: data}` instead of tuples
2. Streaming signals no longer wrapped in `{:agent_signal, ...}` tuple
3. All data is in the `data` field of the signal
4. Entity context available via `signal.subject`

## For Tool/Action Authors

### Non-signal ID generation

```elixir
# Before
alias Jido.Signal.ID
id = ID.generate!()

# After — use Uniq.UUID directly for non-signal entities
id = Uniq.UUID.uuid7()
```

## Signal Catalog

See `docs/signal-catalog.md` for the complete registry of all signal types, their data schemas, source URIs, and handling patterns.
