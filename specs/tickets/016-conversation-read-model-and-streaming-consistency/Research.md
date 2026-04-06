# Research: Conversation Read Model And Streaming Consistency

## Objective

Determine why live UI streaming can fail to show tool-call state that later appears after completion or refresh, and decide whether the issue is a local rendering bug or a broader architectural split between live and persisted conversation rendering.

## Findings

### 1. The UI currently has two separate conversation rendering paths

- The live path is owned by `MurmurWeb.WorkspaceLive` and stores transient per-session streaming state in an ad hoc map shaped like `%{content, thinking, tool_calls, usage}`.
- The refresh/completed path loads thread history through `MurmurWeb.Live.WorkspaceState.load_messages_for_session/1`, which reads live or thawed agent state and then projects thread entries through `JidoMurmur.UITurn.project_entries/1` into canonical `JidoMurmur.DisplayMessage` values.
- `JidoMurmurWeb.Components.ChatStream` renders the live path, while `JidoMurmurWeb.Components.ChatMessage` renders the completed path.

This means Murmur does not yet have one canonical conversation read model that covers both in-progress and completed turns.

### 2. Live tool-call visibility is vulnerable to signal ordering across different PubSub topics

- `JidoMurmur.StreamingPlugin` forwards `ai.llm.response`, `ai.tool.result`, and related signals on the agent stream topic.
- `JidoMurmur.Runner` emits `murmur.message.completed` on the agent messages topic after the run completes.
- `MurmurWeb.WorkspaceLive` marks the agent idle and resets `:streaming` when `murmur.message.completed` arrives.
- `MurmurWeb.WorkspaceLive` also explicitly ignores `ai.llm.response` and `ai.tool.result` signals when the agent is already idle, treating them as stale.

Because the completion signal and stream signals arrive through different PubSub topics, the LiveView can process `murmur.message.completed` before a late `ai.llm.response` or `ai.tool.result`, then discard the late signal. When that happens, the live UI misses tool-call state even though the underlying thread later contains the full assistant/tool data.

### 3. The live path is weaker than the persisted path even without the race

- `JidoMurmur.StreamingPlugin` forwards `ai.tool.started`, but `MurmurWeb.WorkspaceLive` does not handle it.
- Live tool rendering depends mainly on `ai.llm.response` to extract pending tool calls and on `ai.tool.result` to merge results into the transient stream map.
- The completed/refresh path rebuilds the assistant turn from thread entries, including thinking and tool call structure assembled by `UITurn`.

So even when timing is favorable, live rendering is driven by a smaller, more fragile model than the one used after completion.

### 4. Conversation read-model ownership is currently duplicated

- `JidoMurmur.AgentHelper.load_messages/1` and `MurmurWeb.Live.WorkspaceState.load_messages_for_session/1` both implement the same live-agent versus thawed-storage loading logic before projecting entries.
- Ticket 015 made the display model cleaner, but it did not unify where conversation history is hydrated and projected.

This duplication increases the cost of fixing the stream-versus-refresh split because there is no single package-owned conversation read boundary yet.

### 5. The live stream path does not currently expose a stable turn identity to the UI

- `Runner` already creates a stable `request_id` for each agent run.
- Persisted assistant turns are later reconstructed around `request_id` and `tool_call_id` semantics in the thread-backed projection path.
- `StreamingPlugin` currently forwards raw `ai.*` signals directly, and `WorkspaceLive` reduces them by `session_id` plus best-effort `call_id` handling instead of one stable turn identifier.

This means the live UI does not currently reduce events around the same turn identity that the completed path already depends on, which makes out-of-order reconciliation weaker than it needs to be.

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| Patch the race only by relaxing the idle guard or reordering signal handling | Smallest change, could fix the immediate visibility bug quickly | Leaves two rendering models in place and does not address live/persisted divergence |
| Keep separate live and persisted paths but enrich the live stream map until it matches completed messages better | Lower churn than a full redesign | Preserves duplicated concepts and keeps UI state ad hoc instead of package-owned |
| Introduce a core-owned conversation projector plus one Murmur-owned UI update contract for both live and persisted output | One source of truth for in-progress and completed turns, clearer ownership, easier testing, and no raw `ai.*` rendering protocol in the UI | Requires a focused architectural cleanup across `jido_murmur`, `jido_murmur_web`, and `murmur_demo` |

## Recommendation

Create a focused follow-up that introduces a core-owned conversation projector for both live and persisted output, then expose one Murmur-owned conversation update contract to UI consumers.

The key idea is not just to fix the timing bug, but to remove the separate rendering models that made the bug possible and hard to reason about. Live streaming signals and persisted thread entries should converge through one package-owned projector or equivalent read boundary, and all facts entering that boundary should be associated with a stable turn identity even when upstream raw signals do not provide one directly.

## References

- `apps/murmur_demo/lib/murmur_web/live/workspace_live.ex`
- `apps/murmur_demo/lib/murmur_web/live/workspace_state.ex`
- `apps/jido_murmur/lib/jido_murmur/streaming_plugin.ex`
- `apps/jido_murmur/lib/jido_murmur/runner.ex`
- `apps/jido_murmur/lib/jido_murmur/ui_turn.ex`
- `apps/jido_murmur_web/lib/jido_murmur_web/components/chat_stream.ex`
- `apps/jido_murmur_web/lib/jido_murmur_web/components/chat_message.ex`