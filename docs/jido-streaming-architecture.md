# Jido Streaming Architecture — How Agent Signals Reach the LiveView

## Problem

When a user sends a message, the LLM response arrives token-by-token via server-sent events. Without streaming, the UI is blank until the full response completes (which can take 10–30 seconds). The question is how to bridge Jido's internal signal system to Phoenix LiveView for real-time rendering.

## Solution

A Jido Plugin (`Murmur.Agents.StreamingPlugin`) that intercepts **all 7 lifecycle signal types** emitted by the ReAct strategy and broadcasts them as a unified event stream via PubSub. The LiveView pattern-matches on signal type to decide what to render.

## Signal Flow: From LLM to LiveView

Understanding this flow is critical. It has four layers of indirection.

```
┌─────────────────────────────────────────────────────────────────────┐
│ 1. ReqLLM HTTP Layer                                                │
│    ReqLLM.stream_text(model, messages, opts)                        │
│    → Returns {:ok, %StreamResponse{stream: lazy_stream}}            │
│    → Stream yields %StreamChunk{type: :content, text: "Hello"}      │
│    → on_result callback fires per-chunk                             │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ on_result callback
┌───────────────────────────▼─────────────────────────────────────────┐
│ 2. ReAct Runner (Task process)                                      │
│    deps/jido_ai/lib/jido_ai/reasoning/react/runner.ex               │
│                                                                     │
│    The runner runs in a Task spawned by the Worker AgentServer.      │
│    It calls stream_with_callbacks() which sets up on_result and      │
│    on_thinking callbacks. Each callback calls emit_stream_delta()    │
│    which sends:                                                     │
│                                                                     │
│      send(owner, {:react_runner, ref, :event, %Event{               │
│        kind: :llm_delta,                                            │
│        data: %{chunk_type: :content, delta: "Hello"}                │
│      }})                                                            │
│                                                                     │
│    The "owner" is the Worker AgentServer process.                   │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ send() to owner pid
┌───────────────────────────▼─────────────────────────────────────────┐
│ 3. Worker AgentServer → Parent AgentServer                          │
│    deps/jido_ai/lib/jido_ai/reasoning/react/worker/strategy.ex      │
│                                                                     │
│    run_stream/5 consumes the Runner's event stream with             │
│    Enum.each/2. Each event is wrapped in a signal:                  │
│                                                                     │
│      Jido.Signal.new!("ai.react.worker.runtime.event",              │
│        %{request_id: id, event: Map.from_struct(event)})            │
│                                                                     │
│    This signal is cast to the Worker AgentServer. The Worker's      │
│    process_runtime_event/2 then emits_parent_event/3 which creates  │
│    an AgentDirective.emit_to_parent directive — forwarding the      │
│    event to the Parent AgentServer.                                 │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ emit_to_parent directive
┌───────────────────────────▼─────────────────────────────────────────┐
│ 4. Parent AgentServer (the agent the user talks to)                 │
│    deps/jido_ai/lib/jido_ai/reasoning/react/strategy.ex             │
│                                                                     │
│    process_worker_event/2 receives the forwarded event. For         │
│    :llm_delta events, apply_runtime_event/2 creates:                │
│                                                                     │
│      Signal.LLMDelta.new!(%{                                       │
│        call_id: llm_call_id,                                        │
│        delta: "Hello",                                              │
│        chunk_type: :content                                         │
│      })                                                             │
│                                                                     │
│    This signal is cast back to self() (the Parent AgentServer).     │
│    signal_routes maps "ai.llm.delta" → Jido.Actions.Control.Noop   │
│                                                                     │
│    ★ THIS IS WHERE THE PLUGIN INTERCEPTS ★                          │
│    handle_signal/2 runs BEFORE signal routing. Our StreamingPlugin  │
│    pattern-matches on "ai.llm.delta", extracts the delta text,      │
│    and broadcasts via PubSub.                                       │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ Phoenix.PubSub.broadcast
┌───────────────────────────▼─────────────────────────────────────────┐
│ 5. LiveView                                                         │
│    lib/murmur_web/live/workspace_live.ex                             │
│                                                                     │
│    Subscribes to "agent_stream:#{session_id}" topic.                │
│    handle_info({:agent_signal, session_id, signal}) pattern-matches │
│    on signal.type:                                                  │
│      "ai.llm.delta" → appends delta to @streaming[session_id]      │
│                        (.content or .thinking based on chunk_type)  │
│      other types    → catch-all, currently no-op (future use)       │
│    Template renders the accumulated text.                           │
│    On {:message_completed, ...}, @streaming is cleared.             │
└─────────────────────────────────────────────────────────────────────┘
```

## Key Insight: Why a Plugin

Jido Plugins define `handle_signal/2` which runs **before** signal routing. This is the framework's designed interception point. All 7 signal types in the ReAct strategy are Noop-routed, making plugins the only clean place to observe them. The alternatives are all worse:

| Approach | Problem |
|---|---|
| Telemetry handler | `[:jido, :ai, :llm, :delta]` is not emitted for runner deltas. The `[:jido, :agent_server, :signal, :*]` events fire but don't carry the delta text content. |
| Override `on_after_cmd/3` | The `ai.llm.delta` signal routes to `Noop`, which is a no-op action. `on_after_cmd` fires after action execution, but there's nothing meaningful to hook into. |
| Custom signal route | Could replace `Noop` with a custom action, but actions shouldn't have transport side-effects (PubSub broadcast). Mixing concerns. |
| Modify the Runner | Framework internals. Would break on upgrades. |

## PubSub Topic Design

We use a **separate topic** for streaming rather than reusing the agent topic:

- Agent topic: `"workspace:#{workspace_id}:agent:#{session_id}"` — for completed messages, errors, status changes
- Stream topic: `"agent_stream:#{session_id}"` — for high-frequency token chunks

This avoids flooding the agent topic with hundreds of tiny messages per response.

## Signal Types Forwarded

The plugin intercepts all 7 ReAct strategy signal types:

| Signal Type | Purpose |
|---|---|
| `ai.llm.delta` | Streaming content/thinking tokens |
| `ai.llm.response` | Complete LLM response |
| `ai.tool.result` | Tool call results |
| `ai.request.started` | Request lifecycle start |
| `ai.request.completed` | Request lifecycle end |
| `ai.request.failed` | Request errors |
| `ai.usage` | Token usage metrics |

All are broadcast as a single unified event:

```elixir
{:agent_signal, session_id, signal}
```

## Signal Data Structure

```elixir
# The signal received in handle_signal/2 (example: ai.llm.delta):
%Jido.Signal{
  type: "ai.llm.delta",
  data: %{
    call_id: "some-uuid",
    delta: "Hello",          # The token text
    chunk_type: :content     # :content | :thinking
  }
}

# The context map:
%{
  agent: %Jido.Agent{id: "session-uuid-here", ...},
  agent_module: Murmur.Agents.Profiles.GeneralAgent,
  plugin: Murmur.Agents.StreamingPlugin,
  ...
}
```

The `agent.id` equals the session ID (set via `Murmur.Jido.start_agent(module, id: session.id)`).

## LiveView Assign Structure

The LiveView maintains a single `@streaming` assign — a map of session_id to streaming state:

```elixir
@streaming = %{
  "session-uuid" => %{content: "Hello world", thinking: "Let me think..."}
}
```

On `{:message_completed, ...}`, the streaming state for that session is reset to `%{content: "", thinking: ""}`.

## Configuration

Streaming is enabled per-agent via the `plugins` option:

```elixir
use Jido.AI.Agent,
  name: "my_agent",
  plugins: [Murmur.Agents.StreamingPlugin],
  ...
```

The `capture_deltas?` config option on the ReAct strategy controls whether the runner emits delta events at all. It defaults to `true` — if it were set to `false`, no `ai.llm.delta` signals would be generated and the plugin would have nothing to intercept.

## Files

- `lib/murmur/agents/streaming_plugin.ex` — Plugin definition; broadcasts `{:agent_signal, session_id, signal}`
- `lib/murmur/agents/profiles/general_agent.ex` — Plugin registered
- `lib/murmur/agents/profiles/code_agent.ex` — Plugin registered
- `lib/murmur_web/live/workspace_live.ex` — Subscribes to stream topic; pattern-matches on signal type
- `lib/murmur_web/live/workspace_live.html.heex` — Renders `@streaming[session_id]` content and thinking

## Relevant Source Files in Dependencies

For future debugging or understanding:

- `deps/req_llm/lib/req_llm/streaming.ex` — ReqLLM streaming orchestration (StreamServer + FinchClient + StreamResponse)
- `deps/req_llm/lib/req_llm/stream_chunk.ex` — Unified chunk format (`%StreamChunk{type, text, ...}`)
- `deps/jido_ai/lib/jido_ai/signals/llm_delta.ex` — Signal definition for `ai.llm.delta`
- `deps/jido_ai/lib/jido_ai/directive/llm_stream.ex` — Directive that spawns the streaming task and emits deltas
- `deps/jido_ai/lib/jido_ai/reasoning/react/runner.ex` — ReAct runner; `emit_stream_delta/5` sends `:llm_delta` events
- `deps/jido_ai/lib/jido_ai/reasoning/react/worker/strategy.ex` — Worker that consumes runner stream, forwards to parent
- `deps/jido_ai/lib/jido_ai/reasoning/react/strategy.ex` — Parent strategy; `apply_runtime_event/2` for `:llm_delta` creates the Signal.LLMDelta and casts to self
- `deps/jido/lib/jido/plugin.ex` — Plugin behaviour definition; `handle_signal/2` callback docs
