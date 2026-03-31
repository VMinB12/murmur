# Research: Multi-Agent Chat Interface

**Feature**: `001-multi-agent-chat`  
**Date**: 2026-03-25

## R1: Jido 2.0 Agent Lifecycle for Session Management

**Decision**: Use `Jido.AgentServer` (GenServer) per agent session, managed via `Murmur.Jido.start_agent/2` and discovered via `Jido.AgentServer.whereis/1`.

**Rationale**: Jido 2.0 provides a built-in `AgentServer` GenServer that wraps an immutable `Jido.Agent` struct. Each AgentServer handles signal routing, directive execution, and state management. Using `Murmur.Jido` (which `use Jido, otp_app: :murmur` sets up) gives us a DynamicSupervisor and Registry for free — no need to create our own `AgentSupervisor` or `AgentRegistry`.

**Alternatives considered**:
- Raw GenServer + DynamicSupervisor + Registry: More boilerplate, duplicates what Jido already provides. Rejected because Jido's agent runtime handles signal routing, directive execution, and child process management.
- Single GenServer for all agents: Would serialize all agent execution. Rejected because agents must run concurrently and independently.

## R2: Async LLM Execution and Token Streaming

**Decision**: Agent profiles use `Jido.AI.Agent` (not plain `Jido.Agent`). Each agent defines `model`, `tools`, and `system_prompt`. LLM execution uses the built-in `ask/2` + `await/2` lifecycle on the AgentServer for async request handling with per-request correlation. Token streaming is achieved via jido_ai's built-in signal emission (`emit_signals?: true`, the default) — the ReAct runtime inside the AgentServer emits `Jido.AI.Reasoning.ReAct.Event` structs with `kind: :llm_delta` for each token. These events are forwarded to Phoenix PubSub via a signal dispatch configured on the agent, and the LiveView subscribes to the agent's topic to receive them.

**Rationale**: `jido_ai` 2.0 provides a complete AI agent lifecycle. `Jido.AI.Agent` wraps ReAct reasoning, tool calling, and LLM interaction inside an AgentServer GenServer. The `ask/await` pattern gives per-request correlation IDs. The runtime's signal emission handles streaming natively — no custom streaming infrastructure or standalone `ReAct.stream/3` usage needed. The AgentServer is the single runtime for each agent session.

**Alternatives considered**:
- Standalone `ReAct.stream/3`: A stateless function returning a lazy Enumerable. Not compatible with our need for long-lived agent processes, concurrent request handling, and directive execution. Rejected.
- Raw `Req` HTTP calls to OpenAI: Would bypass Jido's tool-calling loop, model aliasing, and ReAct reasoning. Rejected.
- `Task.Supervisor.async_nolink` outside Jido: Bypasses Jido's directive system and loses request correlation. Rejected.
- Synchronous LLM calls in GenServer: Would block the GenServer, violating FR-013a. Rejected.

## R3: PubSub Topic Design

**Decision**: Topic format `"workspace:{workspace_id}:agent:{agent_session_id}"`. The LiveView subscribes to one topic per active agent session.

**Rationale**: Scoping by workspace_id + agent_session_id ensures messages are routed only to the correct LiveView and agent column. Using agent_session_id (not profile_id) supports multiple instances of the same profile in one workspace.

**Alternatives considered**:
- Single workspace topic with filtering: Would require client-side filtering of all agent messages. Rejected for unnecessary bandwidth.
- Process-based messaging (direct pid sends): Would break on LiveView reconnect since pids change. PubSub topics are stable across reconnects. Rejected.

## R4: Mid-Turn Pending Message Injection (Tell + User-to-Busy-Agent)

**Decision**: The AgentServer holds a `pending_injections` list in its agent state. When a message arrives (from user or another agent) while the agent is busy, it's appended to this list. The running ReAct execution drains this queue before its next LLM invocation via a synchronous `GenServer.call(:get_and_clear_injections)`. Drained messages are merged into the conversation context for the next iteration.

**Rationale**: Mid-turn injection is a core Murmur differentiator — agents must be reactive during a turn, not just between turns. This implements the spec's design principle that humans and agents interact with agents the same way. The same injection path handles both FR-012 (busy tell) and FR-017 (busy user message). The synchronous drain ensures no messages are lost between check and LLM call.

**Note on jido_ai**: `Jido.AI.Agent`'s built-in `ask/2` supports concurrent requests, but those are queued and execute sequentially (the next request starts only after the current one completes). This is insufficient for FR-012's requirement that messages are injected *before the agent's next processing step* within an ongoing turn. The `pending_injections` mechanism is custom orchestration on top of Jido's runtime — implemented either via a custom `request_transformer` that drains the queue between ReAct iterations, or by extending the agent's `on_before_cmd/3` callback. This is the one area where we intentionally go beyond jido_ai's built-in lifecycle.

**Alternatives considered**:
- Queueing messages via `ask/2` for after current turn completes: Simpler (uses jido_ai natively) but would add latency to inter-agent communication — agents would not be responsive until their current turn finishes. **Rejected per FR-012**: mid-turn injection is the critical reactive collaboration feature.
- Using Jido Signals for injection: Signals are routed to actions via the AgentServer's signal router, but modifying the in-flight execution's conversation context requires access from within the running ReAct loop. A `GenServer.call` to the AgentServer from the `request_transformer` is the cleanest approach.

## R5: Persistence Strategy (Per-Turn, Per-Agent)

**Decision**: Persist each agent's full message history after each complete agent turn (one request→response cycle including all tool calls). Write via the `Chat` context module. Triggered by the AgentServer when it receives a `{:completed, final_history}` message from the execution Task.

**Rationale**: Per-turn persistence (Option B from spec clarifications) balances durability with write efficiency. If the process crashes mid-turn, at most one in-progress response is lost — which the user would see as incomplete anyway. Each agent persists independently; no cross-agent coordination needed.

**Alternatives considered**:
- Per-token persistence: Extreme write amplification for no user benefit. Rejected.
- Per-step (each model + tool call): Higher write volume, marginal durability gain. Rejected.
- Only when idle: Could lose multiple turns if the agent processes chained injections. Rejected.

## R6: LiveView Reconnect and State Rehydration

**Decision**: On LiveView mount (and remount after disconnect), the LiveView calls `Jido.AgentServer.state/1` for each active agent session to get current history and status. If an agent is currently streaming, the LiveView re-subscribes to its PubSub topic and immediately begins receiving new tokens.

**Rationale**: Agent execution is server-side and independent of browser state (FR-013a). The GenServer holds the authoritative state. On reconnect, the LiveView reads this state and reconstructs streams. Any tokens emitted during the disconnect window are in the GenServer's in-memory history, which is returned on `state/1`.

**Alternatives considered**:
- Persisting streaming state to DB and reading on reconnect: Adds complexity; the GenServer already holds current state. Rejected.
- Buffering all tokens in the GenServer for replay: Unnecessary — the full current history (including partial response) is available via `state/1`. Rejected.

## R7: Inter-Agent Loop Depth Limiting

**Decision**: Track `hop_count` in each inter-agent message. The `TellAction` increments the counter. If `hop_count >= 5`, the action returns an error to the calling agent indicating the loop limit has been reached.

**Rationale**: Simple counter-based approach. The hop count travels with the message metadata, so each agent can independently decide whether to honor a tell request. No global coordinator needed.

**Alternatives considered**:
- Global workspace-level loop tracker: Would require shared mutable state across agents. Rejected for added complexity.
- Time-based TTL: Harder to reason about; execution time varies by LLM. Rejected.

## R8: Agent Profile Catalog Design

**Decision**: Define agent profiles as `Jido.AI.Agent` modules under `Murmur.Agents.Profiles.*`. The `Murmur.Agents.Catalog` module maps profile IDs to `{agent_module, display_metadata}` where display metadata is only UI-specific fields (`description`, `color`). Agent identity (`model`, `system_prompt`, `tools`) lives in the `Jido.AI.Agent` module itself — not duplicated in a separate struct.

**Rationale**: The spec states the catalog is hardcoded at startup. Since each agent profile is already a `Jido.AI.Agent` module declaring its own `model`, `tools`, and `system_prompt`, the catalog only needs to add the display bits that Jido doesn't know about. This avoids duplicating agent configuration in two places (YAGNI, DRY).

**Alternatives considered**:
- Separate profile structs duplicating model/tools/system_prompt: Creates two sources of truth for agent identity. Rejected because `Jido.AI.Agent` already owns this configuration.
- Database-backed catalog: Over-engineering for v1 where catalog is static. Rejected.
- YAML/JSON config files: Adds a parsing step and loses compile-time guarantees. Rejected.

## R9: Jido.Thread as Single Source of Truth for Conversation History (Alignment Refactor)

**Decision**: Replace the custom `Chat.Message` Ecto schema and `Chat` context with `Jido.Thread` as the canonical conversation history. Each agent already has a Thread via the default `Jido.Thread.Plugin`. Thread entries (`:message`, `:tool_call`, `:tool_result`, `:instruction_start`, `:instruction_end`) replace our `messages` table rows.

**Rationale**: The v1 implementation maintained two parallel histories — a Jido Thread in-memory (used by the ReAct strategy for LLM context) and an Ecto `messages` table (used for display and rehydration). This is dual bookkeeping. Jido.Thread already provides append-only semantics, automatic sequencing, revision tracking, and entry filtering by kind. Using it as the single source of truth eliminates the `Chat` context, `Message` schema, and the `messages` migration entirely.

For the LiveView display, Thread entries are projected to display-friendly structs. The `Jido.AI.Thread` extension (from `jido_ai`) provides role-based messaging and provider-agnostic projection.

**Alternatives considered**:
- Keep both: Custom Ecto table for display, Thread for LLM context. Rejected because it creates two sources of truth and requires sync logic.
- Use Thread only in-memory, no DB persistence: Would lose history on agent crash. Rejected — we need persistence via `Jido.Persist`.

## R10: Jido.Persist with Ecto Storage Adapter for Durable History (Alignment Refactor)

**Decision**: Use `Jido.Persist.hibernate/2` and `Jido.Persist.thaw/3` for agent state persistence. Implement a custom `Murmur.Storage.Ecto` adapter that satisfies the `Jido.Storage` behaviour (6 callbacks: `get_checkpoint/2`, `put_checkpoint/3`, `delete_checkpoint/2`, `load_thread/2`, `append_thread/3`, `delete_thread/2`). This adapter stores checkpoints and thread journals in two Ecto tables (`jido_checkpoints` and `jido_thread_entries`).

**Rationale**: Jido's Persist system separates checkpoints (agent state snapshots, overwrite semantics) from journals (thread entries, append-only). The checkpoint stores the full agent state minus the thread, plus a thread pointer. The journal stores thread entries with optimistic concurrency via `expected_rev`. This design keeps checkpoints small regardless of thread length, and gives us hibernate/thaw semantics — snapshot the agent before shutdown, restore it on restart.

The built-in `Jido.Storage.ETS` adapter is ephemeral (dev only) and `Jido.Storage.File` is single-node. An Ecto adapter provides durable persistence across restarts and scales with PostgreSQL.

**Alternatives considered**:
- Continue using custom `messages` table: Doesn't capture full agent state (strategy state, memory, thread rev). Rejected.
- Use `Jido.Storage.File`: Not suitable for multi-process production environments. Rejected.

## R11: Direct AgentServer.cast/2 + Telemetry for Communication (Alignment Refactor)

**Decision**: Replace the custom `PubSubBridge` module with direct communication patterns:

1. **User input → Agent**: LiveView calls `AgentServer.cast(pid, signal)` with a user message signal. The signal routes through the agent's signal router to the ReAct strategy.
2. **Streaming tokens → LiveView**: The LiveView process attaches a telemetry handler for `[:jido, :ai, :llm, :delta]` events scoped to the specific agent. Delta events are sent to the LiveView pid, which updates the UI.
3. **Completed response → LiveView**: The agent's `default_dispatch` is configured as `{:pubsub, target: Murmur.PubSub, topic: "workspace:{wid}:agent:{sid}"}`. When the agent emits request-completed signals, they dispatch to PubSub and the LiveView receives them.
4. **Status changes**: Observed via the same signal dispatch — the agent emits status signals through its effect policy.

**Rationale**: The PubSubBridge wraps `ask/await` in a `Task.Supervisor.start_child`, then manually broadcasts results. This bypasses Jido's signal system. `AgentServer.cast/2` is already async — the agent processes the signal in its own supervised context. Using `default_dispatch` for output means agent Emit directives naturally flow to PubSub, which the LiveView subscribes to.

For streaming tokens specifically, jido_ai uses `:telemetry.execute` (not Emit directives), so we attach telemetry handlers rather than relying on `default_dispatch`. This is the correct integration point — it's how jido_ai is designed to expose streaming data.

**Alternatives considered**:
- Keep PubSubBridge: Works but duplicates Jido's signal/dispatch system and adds a custom Task.Supervisor layer. Rejected.
- Use only `default_dispatch` for everything including streaming: jido_ai emits tokens via telemetry, not directives. Rejected as incompatible with the framework's design.
- Use a Jido Sensor for LiveView input: Possible but overengineering — the LiveView can cast signals directly. Rejected for YAGNI.

## R12: Reconnect via Jido.Persist.thaw/3 (Alignment Refactor)

**Decision**: On LiveView mount/reconnect, check if the AgentServer is still running. If yes, use `Jido.AgentServer.state/1` to get current state (unchanged from v1). If the AgentServer has crashed and not restarted, use `Jido.Persist.thaw/3` with the Ecto storage adapter to reconstruct the agent from the last checkpoint + thread journal. This covers the case where the supervision tree restarted the process but the old state was lost.

**Rationale**: v1 only reloads from the Ecto `messages` table, which loses strategy state, memory, thread revisions, and any in-progress tool call context. `thaw/3` reconstructs the full cognitive state — thread, memory, strategy state — from the durable checkpoint. This aligns with Jido's persistence design where hibernate/thaw is the proper lifecycle for agent state across restarts.

**Alternatives considered**:
- Continue reading from Ecto messages: Loses cognitive state. Rejected.
- Only rely on GenServer staying alive: No durability guarantee. Rejected.
