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

**Decision**: Agent execution happens within the AgentServer via Jido's directive system. LLM calls are non-blocking — the AgentServer dispatches a `RunInstruction` directive that executes in an async Task. Tokens stream back via PubSub broadcasts.

**Rationale**: The Jido AgentServer processes directives asynchronously. The `Directive.RunInstruction` can spawn async work. Token streaming is achieved by having the LLM action emit `{:token, message_id, token_string}` signals via PubSub during execution. The LiveView subscribes to the agent's PubSub topic and uses `stream_insert` to append tokens.

**Alternatives considered**:
- `Task.Supervisor.async_nolink` outside Jido: Bypasses Jido's directive system and loses integration with the agent's state machine. Rejected.
- Synchronous LLM calls in GenServer: Would block the GenServer, violating FR-013a (agents must continue regardless of browser state). Rejected.

## R3: PubSub Topic Design

**Decision**: Topic format `"workspace:{workspace_id}:agent:{agent_session_id}"`. The LiveView subscribes to one topic per active agent session.

**Rationale**: Scoping by workspace_id + agent_session_id ensures messages are routed only to the correct LiveView and agent column. Using agent_session_id (not profile_id) supports multiple instances of the same profile in one workspace.

**Alternatives considered**:
- Single workspace topic with filtering: Would require client-side filtering of all agent messages. Rejected for unnecessary bandwidth.
- Process-based messaging (direct pid sends): Would break on LiveView reconnect since pids change. PubSub topics are stable across reconnects. Rejected.

## R4: Pending Message Injection (Tell + User-to-Busy-Agent)

**Decision**: The AgentServer holds a `pending_injections` list in its state. When a message arrives (from user or another agent) while the agent is busy, it's appended to this list. The running execution drains this queue before its next LLM invocation via a synchronous `GenServer.call(:get_and_clear_injections)`.

**Rationale**: This implements the spec's core design principle that humans and agents interact with agents the same way. The same injection path handles both FR-012 (busy tell) and FR-017 (busy user message). The synchronous drain ensures no messages are lost between check and LLM call.

**Alternatives considered**:
- Queueing messages and processing after current execution completes: Would add latency to inter-agent communication and prevent mid-execution context injection. Rejected per spec requirement FR-012.
- Using Jido Signals for injection: Signals are routed to actions via the AgentServer's signal router -- but modifying the in-flight execution's message history requires direct state access from the running Task. A `GenServer.call` to the AgentServer is the cleanest approach. Decision stands.

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

**Decision**: Define agent profiles as a hardcoded Elixir module (`Murmur.Agents.Catalog`) returning a list of maps. Each profile specifies a Jido Agent module, display metadata, and available tools.

**Rationale**: The spec states the catalog is hardcoded at startup. A simple module with a function returning a list is the most straightforward approach (YAGNI). Each profile maps to a Jido Agent module that defines the agent's schema, strategy, and signal routes.

**Alternatives considered**:
- Database-backed catalog: Over-engineering for v1 where catalog is static. Rejected.
- YAML/JSON config files: Adds a parsing step and loses compile-time guarantees. Rejected.
