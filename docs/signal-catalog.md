# Signal Event Catalog

All PubSub messages in the Murmur ecosystem use `%Jido.Signal{}` envelopes following CloudEvents v1.0.2.

## Signal Types

| Type | Source | Subject Pattern | Data Fields | Emitter Module | PubSub Topic |
|------|--------|----------------|-------------|----------------|--------------|
| `artifact.{name}` | `/jido_artifacts/{name}` | `/agents/{sid}` | `name`, `data`, `mode`, `merge_result?`, `scope` | `JidoArtifacts.ArtifactPlugin` | `workspace:{wid}:agent:{sid}:artifacts` |
| `murmur.message.completed` | `/jido_murmur/runner` | `/workspaces/{wid}/agents/{sid}` | `session_id`, `response` | `JidoMurmur.Runner` | `workspace:{wid}:agent:{sid}:messages` |
| `murmur.message.received` | `/jido_murmur/tell_action` | `/workspaces/{wid}/agents/{sid}` | `session_id`, `message` | `JidoMurmur.TellAction`, `JidoTasks.Tools.AddTask` | `workspace:{wid}:agent:{sid}:messages` |
| `murmur.request.failed` | `/jido_murmur/runner` | `/workspaces/{wid}/agents/{sid}` | `session_id`, `reason` | `JidoMurmur.Runner` | `workspace:{wid}:agent:{sid}:messages` |
| `task.created` | `/jido_tasks/tools/add_task` | `/workspaces/{wid}/tasks/{tid}` | `task` | `JidoTasks.Tools.AddTask`, `MurmurWeb.WorkspaceLive` | `workspace:{wid}:tasks` |
| `task.updated` | `/jido_tasks/tools/update_task` | `/workspaces/{wid}/tasks/{tid}` | `task` | `JidoTasks.Tools.UpdateTask`, `MurmurWeb.WorkspaceLive` | `workspace:{wid}:tasks` |
| `ai.llm.delta` | (jido_ai) | `/agents/{sid}` | `delta`, `chunk_type` | jido_ai ReAct strategy | `workspace:{wid}:agent:{sid}:stream` |
| `ai.llm.response` | (jido_ai) | `/agents/{sid}` | `response` | jido_ai ReAct strategy | `workspace:{wid}:agent:{sid}:stream` |
| `ai.tool.result` | (jido_ai) | `/agents/{sid}` | `tool_name`, `result` | jido_ai ReAct strategy | `workspace:{wid}:agent:{sid}:stream` |
| `ai.request.started` | (jido_ai) | `/agents/{sid}` | `request_id` | jido_ai ReAct strategy | `workspace:{wid}:agent:{sid}:stream` |
| `ai.request.completed` | (jido_ai) | `/agents/{sid}` | `request_id` | jido_ai ReAct strategy | `workspace:{wid}:agent:{sid}:stream` |
| `ai.request.failed` | (jido_ai) | `/agents/{sid}` | `error` | jido_ai ReAct strategy | `workspace:{wid}:agent:{sid}:stream` |
| `ai.usage` | (jido_ai) | `/agents/{sid}` | `input_tokens`, `output_tokens`, `total_tokens`, `model`, `duration_ms` | jido_ai ReAct strategy | `workspace:{wid}:agent:{sid}:stream` |

## Typed Signal Modules

These modules provide constructors with schema validation via `use Jido.Signal`:

| Module | Type | Location |
|--------|------|----------|
| `JidoMurmur.Signals.MessageCompleted` | `murmur.message.completed` | `apps/jido_murmur/lib/jido_murmur/signals/message_completed.ex` |
| `JidoMurmur.Signals.MessageReceived` | `murmur.message.received` | `apps/jido_murmur/lib/jido_murmur/signals/message_received.ex` |
| `JidoTasks.Signals.TaskCreated` | `task.created` | `apps/jido_tasks/lib/jido_tasks/signals/task_created.ex` |
| `JidoTasks.Signals.TaskUpdated` | `task.updated` | `apps/jido_tasks/lib/jido_tasks/signals/task_updated.ex` |

## PubSub Topics

All topics are constructed via `JidoMurmur.Topics`:

| Function | Pattern | Usage |
|----------|---------|-------|
| `agent_messages/2` | `workspace:{wid}:agent:{sid}:messages` | Message completed, received, request failed |
| `agent_stream/2` | `workspace:{wid}:agent:{sid}:stream` | AI streaming signals (delta, tool result, usage) |
| `agent_artifacts/2` | `workspace:{wid}:agent:{sid}:artifacts` | Artifact create/update signals |
| `workspace_tasks/1` | `workspace:{wid}:tasks` | Task created/updated signals |

## Handler Patterns

All `handle_info/2` handlers match on `%Jido.Signal{}` struct fields:

```elixir
# Match by exact type
def handle_info(%Jido.Signal{type: "task.created", data: %{task: task}}, socket)

# Match by type prefix (artifact signals have dynamic names)
def handle_info(%Jido.Signal{type: "artifact." <> _name, data: data}, socket)

# Match streaming signals directly (no wrapper tuple)
def handle_info(%Jido.Signal{type: "ai.llm.delta", data: data} = signal, socket)
```

## How to Add a New Signal Type

1. **Create a typed signal module** using `use Jido.Signal`:

   ```elixir
   defmodule MyApp.Signals.MyEvent do
     use Jido.Signal,
       type: "myapp.my_event",
       default_source: "/myapp/emitter",
       schema: [
         field_a: [type: :string, required: true],
         field_b: [type: :any, required: false]
       ]

     def subject(workspace_id, entity_id),
       do: "/workspaces/#{workspace_id}/entities/#{entity_id}"
   end
   ```

2. **Add tests** in the corresponding `test/signals/` directory.

3. **Broadcast the signal** from the producer:

   ```elixir
   signal = MyApp.Signals.MyEvent.new!(
     %{field_a: "value"},
     subject: MyApp.Signals.MyEvent.subject(workspace_id, entity_id)
   )
   Phoenix.PubSub.broadcast(pubsub, topic, signal)
   ```

4. **Handle the signal** in the consumer:

   ```elixir
   def handle_info(%Jido.Signal{type: "myapp.my_event", data: data}, socket) do
     # ...
   end
   ```

5. **Update this catalog** with the new signal type, source, subject pattern, and data fields.
