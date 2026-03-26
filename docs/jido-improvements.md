# Jido Integration Improvements

Audit of areas where Murmur hand-rolls infrastructure that Jido already provides, and Jido features that could improve the codebase further.

## 1. PendingQueue + Runner vs Jido Signals

### Current approach

Three custom modules collaborate to handle message queuing during active ReAct loops:

- **`PendingQueue`** — ETS `duplicate_bag` holding messages for busy agents
- **`Runner`** — Task-based drain loop with ETS locking (`@active_table`) that manages the ask→await→hibernate lifecycle
- **`MessageInjector`** — `Jido.AI.Reasoning.ReAct.RequestTransformer` that drains `PendingQueue` before each LLM API call

### Why Jido Signals cannot replace this

**The PendingQueue exists for a specific reason that Jido Signals do not address.**

The critical requirement is: new messages must be injected into the conversation **mid-ReAct-loop**, between tool execution and the next LLM API call — not queued for after the loop completes.

Jido's signal processing model is sequential at the `AgentServer` level:

> "Signal processing runs one at a time. If a synchronous call is in flight and an async signal arrives, the async signal is deferred until the current call completes."
> — [agent-runtime.md](../.agents/skills/jido/agent-runtime.md)

The ReAct strategy uses `tick/2` to iterate its reasoning loop. Each tick is an internal cycle within a single signal's processing scope. A new inbound signal (e.g., a user message arriving as a `cast/2`) would be **deferred** by `AgentServer` until the entire ReAct loop finishes — which is exactly the behavior you went out of your way to avoid.

The `RequestTransformer` callback (`transform_request/4`) is the correct Jido extension point for this. It fires before every LLM call within the ReAct loop, giving you a hook to inject additional context. The ETS-backed `PendingQueue` is the sideband that feeds that hook, and it works precisely because it bypasses the `AgentServer` mailbox.

### Verdict: Keep the current architecture

The PendingQueue + MessageInjector design is **correct and idiomatic** for this use case. It uses the Jido-provided `RequestTransformer` hook and only reaches outside Jido for the ETS sideband — which is necessary because `AgentServer` cannot deliver mid-loop messages.

### Possible refinements (not replacements)

- **Add telemetry** to `PendingQueue.enqueue/2` and `MessageInjector.transform_request/4` so you can observe injection timing in the dashboard
- **Add a monotonic sequence** to `PendingQueue` entries (already doing this with `System.monotonic_time/1` — good)
- **Consider a GenServer wrapper** around the ETS table to add backpressure if the queue grows unbounded during long ReAct loops

---

## 2. ~~Runner status broadcasts → Jido Telemetry events~~ ✅

**Completed**: Added `Jido.Telemetry.setup()` to `application.ex`. This attaches structured logging for all agent commands (`cmd:start/stop/exception`), signal processing, directive execution, strategy ticks, and queue overflows. Runner broadcasts are kept — they serve a different purpose (LiveView ↔ Runner communication) that telemetry doesn't replace.

### Current approach

`Runner` manually broadcasts status via Phoenix PubSub:

```elixir
broadcast(topic, {:message_completed, session_id, response})
broadcast(topic, {:request_failed, session_id, reason})
```

`workspace_live.ex` subscribes and pattern-matches on 5+ tuple shapes.

### What Jido provides

Jido emits standard `:telemetry` events for all agent commands and signal processing:

| Event | When |
|---|---|
| `[:jido, :agent, :cmd, :start]` | Command execution begins |
| `[:jido, :agent, :cmd, :stop]` | Command execution completes |
| `[:jido, :agent, :cmd, :exception]` | Command raises |
| `[:jido, :agent_server, :signal, :start\|:stop\|:exception]` | Signal processing lifecycle |

### Recommendation

1. Call `Jido.Telemetry.setup()` in `application.ex`
2. Attach telemetry handlers that translate Jido events into the PubSub messages your LiveView expects
3. Remove the manual `broadcast/2` calls from `Runner`

This keeps the LiveView subscription model unchanged while eliminating hand-rolled status tracking. The `Runner` would only be responsible for ask/await orchestration and hibernation.

---

## 3. ~~Telemetry module — forward actual delta content~~ ✅

**Completed**: Removed `Murmur.Agents.Telemetry` — it was dead code (never called, produced `{:streaming_active, ...}` that nothing listened to). The telemetry delta event `[:jido, :ai, :llm, :delta]` doesn't carry token text anyway — it's just a notification. Streaming token display in the LiveView template stays (it's wired up and tested), but needs a real producer as a separate feature.

### Original approach

`Murmur.Agents.Telemetry` listened to `[:jido, :ai, :llm, :delta]` but only sent a generic `:streaming_active` message — the actual token content is discarded.

---

## 4. Catalog (agent registry) → Jido Discovery

### Current approach

`Murmur.Agents.Catalog` is a static `@profiles` map of profile IDs → `{module, metadata}`.

### What Jido provides

Jido has a Discovery catalog that automatically registers agents, actions, skills, and sensors at compile time. Agents defined with `use Jido.AI.Agent` are discoverable through the catalog API.

### Recommendation

Low priority — the static map works fine for 2 profiles. Consider switching when the profile count grows or if you add `jido_live_dashboard` (which reads from Discovery).

---

## 5. Add `jido_live_dashboard` for agent debugging

### Current state

Agent debugging requires manual `Jido.AgentServer.state/1` calls. Phoenix LiveDashboard is already in deps but has no Jido integration.

### What it provides

`jido_live_dashboard` adds four pages to Phoenix LiveDashboard with a single function call:

- **Home** — System status, running agent count, trace buffer stats
- **Discovery** — Browse registered Actions, Agents, Skills, Sensors
- **Runtime** — Live AgentServer process table with per-agent state inspection
- **Traces** — Telemetry event viewer with span hierarchy and trace correlation

### Recommendation

Add to `mix.exs`:

```elixir
{:jido_live_dashboard, github: "agentjido/jido_live_dashboard"}
```

Update the LiveDashboard route in `router.ex`:

```elixir
live_dashboard "/dashboard",
  metrics: MurmurWeb.Telemetry,
  additional_pages: JidoLiveDashboard.pages()
```

This is a high-value, low-effort win — zero custom code, immediate operational visibility.

---

## 7. Add `jido_memory` for persistent agent context

### Current state

Agents have no memory beyond the conversation thread. Context from previous conversations is lost when an agent is stopped.

### What it provides

`jido_memory` provides:

- Structured memory records with namespace-aware storage
- remember/recall/forget actions that compose with the Jido action system
- A plugin that mounts directly into agents for lifecycle-integrated memory
- Auto-capture hooks for LLM signal flows

### Recommendation

Medium priority — useful once agents need to retain user preferences, facts, or task context across conversation sessions. The plugin model means it can be added to existing agents without changing their core logic:

```elixir
use Jido.AI.Agent,
  name: "general_agent",
  plugins: [Jido.Memory.Plugin],
  # ...existing config...
```

---

## 8. Use Jido Signals for inter-component communication

### Current approach

LiveView ↔ Runner communication uses raw PubSub tuples:

```elixir
{:message_completed, session_id, response}
{:request_failed, session_id, reason}
{:streaming_token, session_id, token}
{:status_change, session_id, status}
```

### What Jido provides

Jido Signals are CloudEvents-typed envelopes with:

- Typed, validated message contracts
- Built-in dispatch adapters (`:pid`, `:pubsub`, `:logger`, `:http`)
- UUID v7 IDs for time-ordered tracing
- Extension system for custom metadata

### Recommendation

Define custom signal types for the application's event vocabulary:

```elixir
defmodule Murmur.Signals.MessageCompleted do
  use Jido.Signal,
    type: "murmur.agent.message.completed",
    default_source: "/agents/runner"
end
```

This gives you typed contracts, makes events auditable, and integrates with `jido_live_dashboard` tracing. Medium priority — the current approach works but doesn't scale well as event types proliferate.
