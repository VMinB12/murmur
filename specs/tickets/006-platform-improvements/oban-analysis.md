# Oban Feasibility Analysis — Scaling, Robustness, and Tradeoffs

## Executive Summary

Oban is a poor fit for Murmur's core LLM request lifecycle. The current `Runner` + `PendingQueue` design is well-suited to the problem domain — long-running, stateful, streaming interactions with in-process agents. Oban would introduce significant complexity without solving the actual bottlenecks. However, Oban could add value for specific peripheral workloads (cleanup, scheduled maintenance, webhook delivery).

This report analyses the full architecture from the perspectives of scaling, performance, robustness, and maintainability, and explains where Oban helps, where it hurts, and what alternatives better address each concern.

---

## 1. Current Architecture Profile

### How an LLM request flows today

```
User types message
  → LiveView handle_event
    → Runner.send_message(session, content)
      → PendingQueue.enqueue(session_id, content)   [ETS write]
      → maybe_start_loop(session)                    [ETS insert_new for mutex]
        → Task.Supervisor.start_child(...)
          → run_loop:
              PendingQueue.drain(session_id)          [ETS take — atomic]
              LLM.Real.ask(agent_module, pid, combined, tool_ctx)
              ├─ ReAct loop iterations (3-15 seconds each)
              │  ├─ MessageInjector.transform_request  [drains more pending msgs]
              │  ├─ StreamingPlugin.handle_signal       [PubSub deltas → LiveView]
              │  └─ Tool calls (tell, arxiv_search, tasks, artifacts)
              LLM.Real.await(agent_module, req, timeout: 120s)
              hibernate_agent(session_id)              [Postgres checkpoint write]
              PubSub.broadcast(:message_completed)     [LiveView picks up final answer]
              run_loop(session)                        [re-drains if more messages queued]
```

### Key architectural properties

| Property | Current State |
|----------|---------------|
| **Concurrency control** | One Runner task per session (ETS mutex via `insert_new`) |
| **Message buffering** | ETS `duplicate_bag` with monotonic timestamps for ordering |
| **Streaming** | PubSub signal pipeline (StreamingPlugin → LiveView) — real-time token delivery |
| **State coupling** | Runner holds reference to live `AgentServer` pid — required for `ask/await` |
| **Persistence** | Agent checkpoint + thread entries written to Postgres after each completed turn |
| **Timeout** | 120s per await; no global timeout for multi-step ReAct loops |
| **Fault domain** | Task crash → ETS mutex released → next incoming message retriggers loop |

---

## 2. Why Oban Is a Poor Fit for the Core LLM Loop

### 2.1 The fundamental mismatch: Oban jobs are stateless; LLM sessions are deeply stateful

Oban workers receive serialized JSON args and execute in isolated processes. Murmur's LLM flow requires:

1. **A live `AgentServer` pid** — `ask/await` operates on the in-memory Jido agent, not a serializable reference. The agent holds compiled strategy state, plugin state, thread history, and a running ReAct loop state machine.

2. **Mid-turn message injection** — `MessageInjector.transform_request/4` is called on *every iteration* of the ReAct loop (not just once per job). It drains the `PendingQueue` to inject messages the agent receives while it's already thinking. An Oban job can't be interrupted mid-execution to merge new inputs.

3. **Real-time streaming** — `StreamingPlugin` broadcasts deltas to the LiveView *during* execution. Oban jobs run in background workers with no guaranteed connection to a specific LiveView process. You'd need an extra PubSub or channel bridge, which you already have — the current design *is* that bridge.

4. **Single-writer guarantee** — The ETS-based mutex (`insert_new`) ensures only one task talks to an agent at a time. Oban's concurrency controls operate at the queue level (global concurrency limits), not at the per-agent-session level. You'd need `unique` constraints keyed on `session_id`, but Oban's uniqueness is based on `args` hashing with period-based windows — it doesn't give you the "exactly one active runner per session" guarantee as cleanly as the current ETS approach.

### 2.2 What Oban's persistence buys you — and why it's less than it seems

The pitch: "If the node restarts, in-flight messages are lost." Let's examine each data path:

| Data | Currently persisted? | Lost on restart? | Oban would help? |
|------|---------------------|-------------------|-------------------|
| **User message text** | LiveView socket only | Yes — the user re-sends on reconnect anyway | Marginally — but message is visible in UI, user knows to resend |
| **Agent conversation history** | Postgres (thread entries + checkpoint) after each completed turn | Only the in-flight turn | No — Oban job would also lose the in-flight ReAct state (`last_request_id`, partial tool results) |
| **Pending queue messages** | ETS only | Yes | Yes — but these are transient by design (see 2.3) |
| **Streaming deltas** | Not persisted | Yes — LiveView reconnect reloads full thread | No — streaming is inherently ephemeral |

**The critical insight:** The `AgentServer` in-memory state (the ReAct strategy state machine, accumulated tool results, partial reasoning) is *not serializable to Oban args*. Even if Oban re-enqueued the job after a crash, the agent would need to be reconstructed from the last checkpoint and the LLM call restarted from scratch. The current design already does this — when a LiveView reconnects, it calls `ensure_agent_started` which thaws the agent from its last checkpoint.

### 2.3 Pending messages are transient by design

`PendingQueue` holds messages between the user pressing send and the Runner picking them up. This window is typically milliseconds to a few seconds. Messages arrive while an agent is already processing — `MessageInjector` drains them mid-turn. If the node dies:

- The user sees the page reload
- The LiveView reconnects and reloads the last persisted thread
- The user sees their last completed exchange and can re-send

Moving this to Postgres via Oban adds latency (a DB write per enqueue + insert per drain) to a hotpath that currently operates in microseconds on ETS.

### 2.4 Complexity cost

Adding Oban to the LLM path requires:

1. **Oban migration** — New Postgres tables for job queue
2. **Job serialization** — Rewrite Runner to serialize `session` struct to JSON args and deserialize back; handle pid lookup in the worker
3. **Streaming bridge** — Oban workers aren't connected to LiveView; need to maintain the PubSub broadcast path anyway
4. **Mid-turn injection rework** — Either abandon mid-turn injection (degrading UX — messages pile up until the full turn completes) or build a side-channel for the Oban worker to poll for new messages
5. **Concurrency control rework** — Replace ETS mutex with Oban unique constraints, handling edge cases around job completion and re-enqueueing
6. **Testing** — Oban's testing framework (`Oban.Testing`) needs setup; existing `Mox`-based LLM mocking needs adaptation

Estimated new/modified modules: 4-6. Lines of code: 200-400+. New dependency surface: Oban + Oban migration + potential Oban Pro/Web for rate limiting.

---

## 3. Scaling Analysis

### 3.1 Current bottlenecks (not addressed by Oban)

**Bottleneck 1: One `Task` per active agent session**

Each active conversation spawns a `Task` under `Jido.task_supervisor_name()`. With 8 agents per workspace and N concurrent workspaces, you get up to `8N` concurrent tasks. Each task blocks on `await` for up to 120s. This is fine for 10-50 concurrent workspaces (80-400 tasks). The BEAM handles this easily.

*Oban impact:* Neutral — Oban workers also use one process per job. The concurrency bound moves from "BEAM processes" to "Oban queue limit", but the actual bottleneck is LLM API throughput, not local process count.

**Bottleneck 2: LLM API rate limits and latency**

Each `ask/await` cycle takes 3-60+ seconds depending on model, prompt length, and number of ReAct iterations. The real scaling limit is API throughput and cost, not local compute.

*Oban impact:* Oban's rate limiting (via Oban Pro/Web) could help here, but `Hammer` (already recommended in your review) is much simpler and doesn't require restructuring the entire execution model. See section 5.

**Bottleneck 3: TeamInstructions DB query per ReAct iteration**

`MessageInjector.transform_request/4` calls `TeamInstructions.build/2` on every LLM iteration, which calls `Workspaces.list_agent_sessions/1` — a Postgres query. In a ReAct loop with 5 iterations, that's 5 DB queries per turn just for the team roster.

*Fix:* Cache the roster in the agent's state or in ETS with a short TTL. This is independent of Oban.

**Bottleneck 4: `load_messages_for_session` on LiveView mount**

On page load, the LiveView calls `load_messages_for_session/1` for every agent session, each of which calls `Jido.AgentServer.state(pid)` or falls back to `thaw` (Postgres read). With 8 agents, that's 8 sequential state fetches.

*Fix:* Parallelize with `Task.async_stream`. Independent of Oban.

### 3.2 Where Oban helps with scaling

Oban's strengths — durable queue, configurable concurrency, rate limiting, scheduled execution — are designed for **background batch processing** where:

- Work is fire-and-forget
- Results arrive eventually (not streamed live)
- Jobs are idempotent and retryable
- Serialized args fully describe the work

Murmur's LLM loop has none of these properties. The UI needs streaming, the agent is stateful, and retrying a failed LLM call from serialized args would lose all ReAct state.

---

## 4. Robustness Analysis

### 4.1 Failure modes and how they're currently handled

| Failure | Current Behavior | Severity | Oban Improvement |
|---------|-----------------|----------|------------------|
| **LLM API timeout** | `await` returns `{:error, reason}` → PubSub broadcasts `:request_failed` → LiveView shows error | Low — user retries | None — job would also timeout |
| **LLM API 500/rate limit** | Same as timeout | Medium — no auto-retry | Marginal — Oban retries, but ReAct state is lost between retries |
| **Agent process crash** | Task's `after` block releases ETS mutex; next message triggers fresh loop | Low — self-healing | None — current design already self-heals |
| **Node restart** | ETS wiped → pending messages lost → LiveView reconnect reloads persisted thread | Medium — one turn lost | Low — Oban job survives, but agent needs full reconstruction |
| **Postgres down** | Hibernate fails (logged) → agent continues in-memory | Low — gracefully degrades | Worse — Oban can't enqueue or dequeue jobs at all |
| **PubSub partition** | Streaming stops → LiveView shows stale data → message_completed eventually arrives | Low | None |

### 4.2 The real robustness gaps (and better fixes)

**Gap 1: No automatic retry on transient LLM failures**

If `ask` returns `{:error, :timeout}` or a 429/503, the user sees an error and must manually retry. This is the strongest case for "something Oban-like."

**Better fix:** Add retry logic directly in `Runner.process_batch/2`:

```elixir
defp process_batch(session, combined, retries \\ 3) do
  case llm_adapter().ask(agent_module, pid, combined, tool_ctx) do
    {:ok, req} ->
      handle_await(agent_module, req, session, topic)
    {:error, reason} when retries > 0 and retryable?(reason) ->
      Process.sleep(backoff(retries))
      process_batch(session, combined, retries - 1)
    {:error, reason} ->
      broadcast(topic, {:request_failed, session.id, reason})
  end
end
```

This preserves the in-process agent state, maintains streaming, and doesn't require a queue abstraction. The agent pid stays valid across retries since it's the same Task execution.

**Gap 2: No timeout on the full ReAct loop**

The `await` timeout is 120s per individual request, but a ReAct loop can make multiple requests. A pathological tool-calling loop could run for minutes.

**Better fix:** Add a total-turn deadline:

```elixir
defp handle_await(agent_module, req, session, topic) do
  deadline = System.monotonic_time(:millisecond) + 180_000
  remaining = deadline - System.monotonic_time(:millisecond)

  case llm_adapter().await(agent_module, req, timeout: min(remaining, 120_000)) do
    # ...
  end
end
```

**Gap 3: Cascading failures via `TellAction`**

An agent can trigger inter-agent messages which start runner loops on other agents. With 5-hop depth limit, worst case is 5 sequential LLM calls triggered by a single user message. The hop limit prevents infinite loops, but there's no overall workspace-level concurrency cap.

**Better fix:** Track active runners per workspace in ETS and reject new messages beyond a threshold, or use `Hammer` for workspace-level rate limiting.

---

## 5. Recommended Alternatives to Oban

### 5.1 For LLM retry and backoff: inline retry in Runner

Add exponential backoff retry directly in `process_batch`:

- Zero additional dependencies
- Preserves agent state across retries
- Preserves streaming
- 15-20 lines of code

### 5.2 For LLM rate limiting: Hammer

Already recommended in the codebase review. Protects against cost spikes from runaway inter-agent chains:

```elixir
# Per-session: max 10 messages per minute
# Per-workspace: max 30 LLM calls per minute
case Hammer.check_rate("llm:workspace:#{workspace_id}", 60_000, 30) do
  {:allow, _} -> Runner.send_message(session, content)
  {:deny, _} -> {:noreply, put_flash(socket, :error, "Rate limit reached.")}
end
```

- Simple, focused library (~100 lines of integration)
- ETS-backed by default — same performance characteristics as current design
- No migrations, no background processes

### 5.3 For persistence of pending messages: optional Postgres fallback

If losing pending messages on restart is truly unacceptable (assess whether it actually is — the window is typically milliseconds):

```elixir
defmodule Murmur.Agents.PendingQueue do
  # Keep the hot path on ETS for performance
  def enqueue(session_id, message) do
    :ets.insert(@table, {session_id, message, System.monotonic_time(:nanosecond)})
    # Optionally persist for crash recovery
    Repo.insert(%PendingMessage{session_id: session_id, content: message})
    :ok
  end

  def drain(session_id) do
    # Drain from ETS (fast path)
    messages = :ets.take(session_id) |> sort_and_extract()
    # Clean up Postgres copies
    if messages != [], do: delete_persisted(session_id)
    messages
  end

  # Called on startup to recover any messages that were pending when node died
  def recover_all do
    PendingMessage |> Repo.all() |> Enum.each(fn pm ->
      :ets.insert(@table, {pm.session_id, pm.content, 0})
    end)
  end
end
```

This is simpler than Oban (one table, one schema) and preserves the hot ETS path.

### 5.4 For background/deferred work: lightweight GenServer queue

If you later need scheduled or background jobs (e.g., "summarize this conversation nightly", "cleanup stale sessions"), a simple GenServer with `Process.send_after` covers most cases. Graduate to Oban *only* when you need:

- Persistence across deploys for background-only (non-interactive) work
- Job priority queues for multiple job types
- Web dashboard for ops visibility
- Cron-like scheduling

---

## 6. Where Oban *Would* Make Sense

Oban becomes a good fit if Murmur grows these features:

| Feature | Why Oban fits |
|---------|---------------|
| **Webhook delivery** — Notify external systems when tasks complete | Fire-and-forget, needs retries, idempotent |
| **Batch summarization** — Nightly digest of workspace activity | Scheduled, background, no streaming needed |
| **Agent memory compaction** — Periodically trim old thread entries | Scheduled, background, idempotent |
| **Export/report generation** — PDF/CSV generation from conversations | Async result, no streaming, retryable |
| **Email notifications** — Alert workspace members of activity | Fire-and-forget, needs retries |

For these workloads, Oban's `cron` plugin, retry semantics, and Postgres-backed durability are genuinely valuable. You could add Oban for *just these* while leaving the LLM loop on the current Runner architecture.

---

## 7. Maintainability Assessment

### Current design: strengths

- **Small surface area** — `Runner` (140 lines), `PendingQueue` (35 lines), `TableOwner` (20 lines). Easy to understand and modify.
- **Clear flow** — Message → enqueue → drain → ask → stream → await → hibernate → broadcast. One file tells the whole story.
- **Testable** — `Mox` on `LLM` behaviour isolates all LLM calls. No infrastructure setup needed.
- **Fault isolation** — Task crash only affects one session. ETS mutex auto-releases.

### Current design: weaknesses

- **No observability** — No metrics on queue depth, runner count, LLM latency, error rates. Add `Telemetry` events to Runner (see recommendation below).
- **Implicit dependencies** — Runner depends on `Murmur.Jido.whereis/1` returning a pid, `PendingQueue` existing, and ETS tables being initialized. These are boot-order dependencies not enforced by the type system.
- **TeamInstructions DB hit per iteration** — Performance and maintainability issue. Should be cached.

### Adding Oban: maintainability impact

- **+2 migrations, +1 config block, +1 worker module, significant rework of Runner**: Net negative for a 2-agent app
- **Testing complexity**: Oban requires `Oban.Testing` setup, drain-in-test patterns, and `perform_job` helpers alongside existing Mox mocks
- **Operational overhead**: Oban dashboard is nice but adds another surface to monitor. Current app has no need for job inspection since the interactive nature means users see results immediately

---

## 8. Concrete Recommendations

### Do now (high impact, low effort)

1. **Add Telemetry events to Runner** — Emit `:murmur, :runner, :start/:stop/:error` events with session_id, duration, error reason. Pipe to LiveDashboard. (~30 lines)

2. **Add inline retry with backoff in Runner.process_batch** — 3 retries, exponential backoff, only on transient errors (timeout, 429, 503). (~20 lines)

### Do later (if needed)

3. **Cache TeamInstructions roster** — ETS cache with 30s TTL or pass roster via tool_ctx. Eliminates N DB queries per ReAct loop. (~15 lines)

4. **Add Hammer for rate limiting** — Per-session and per-workspace LLM call caps. Prevents runaway inter-agent chains from blowing API budgets. (~20 lines of integration)

5. **Persist pending messages** — Dual-write to ETS + Postgres for crash recovery. Only if message loss on restart is actually causing user pain. (~40 lines + 1 migration). No user pain for now, so defer until you see it.

6. **Add Oban for peripheral jobs** — When webhook delivery, scheduled reports, or batch processing is needed. Don't route LLM calls through it.

### Don't do

7. **Don't route LLM calls through Oban** — The stateful, streaming, interactive nature of the ReAct loop is fundamentally incompatible with Oban's stateless job model. The refactoring cost is high, the reliability gains are marginal, and you'd lose mid-turn message injection and seamless streaming.

---

## 9. Decision Matrix

| Concern | Current Design | With Oban (LLM path) | Recommended |
|---------|---------------|----------------------|-------------|
| **Streaming** | Native via PubSub | Needs bridge layer | Keep current |
| **Mid-turn injection** | Native via MessageInjector | Would need side-channel | Keep current |
| **Retry on failure** | None | Built-in | Add inline retry in Runner |
| **Rate limiting** | None | Oban Pro ($) | Hammer (free, simple) |
| **Message persistence** | ETS (ephemeral) | Postgres (durable) | Dual-write if needed |
| **Observability** | None | Oban Web ($) | Telemetry + LiveDashboard |
| **Background jobs** | N/A | Excellent fit | Add Oban when needed |
| **Complexity** | Low (~195 lines) | High (~400+ lines + config) | Keep low |
| **Testing** | Mox mock, simple | Oban.Testing + Mox | Keep simple |
