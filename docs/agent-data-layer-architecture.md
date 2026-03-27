# Agent Data Layer Architecture — Beyond Messages

## Problem Statement

Murmur agents currently stream only **conversation events** (LLM deltas, tool calls, completed messages) to the frontend. The `StreamingPlugin` intercepts ReAct strategy signals and broadcasts them over PubSub; the LiveView renders them as chat bubbles.

We need agents that can **produce and display structured data** beyond messages. Three motivating use cases:

1. **Arxiv agent** — A `search` tool returns papers. The UI should display all papers found across multiple searches as a card grid. Clicking a paper opens an iframe/PDF viewer. A `display` tool shows a single PDF with highlighted paragraphs.

2. **SQL agent** — A `query` tool runs SQL and returns results. The agent sees a truncated text representation; the user sees the full result as a formatted table. A `display` tool presents a query + results pair as a named artifact.

3. **Collaborative document** — A writer agent, review agent, and human user all edit a shared document. All parties must see each other's edits in real time.

Use cases 1 and 2 are **single-agent state** — one agent accumulates data that the frontend renders. Use case 3 is **shared state** — multiple agents and a human modify the same structure.

## Current Architecture (Status Quo)

```
Agent (Jido AgentServer)
  ├─ ReAct strategy executes LLM + tools
  ├─ Emits signals: ai.llm.delta, ai.tool.result, ai.request.completed, etc.
  └─ StreamingPlugin.handle_signal/2 intercepts ALL signals
       └─ PubSub.broadcast("agent_stream:#{session_id}", {:agent_signal, sid, signal})

LiveView (workspace_live.ex)
  ├─ Subscribes to "agent_stream:#{session_id}" for streaming tokens
  ├─ Subscribes to "workspace:#{wid}:agent:#{sid}" for completed messages
  ├─ Maintains @messages (map of session_id → list of projected thread entries)
  ├─ Maintains @streaming (map of session_id → %{content: "", thinking: ""})
  └─ On :message_completed, reloads full history from agent Thread
```

Key observations:
- Data flows one way: Agent → PubSub → LiveView
- The only "state" visible to the frontend is the Thread (conversation log) and ephemeral streaming deltas
- There is **no mechanism** for agents to expose structured data other than as message text or tool call arguments/results
- The LiveView has no concept of agent "artifacts" or "data panes"

## Design Constraints

1. **Jido primitives must be respected**. Agents are pure data structs. Side effects flow through Directives. Signals are the message envelope. Plugins are the interception point.

2. **Agent logic must remain pure**. Tools should not directly call PubSub or push to LiveView. Data emission must go through the existing signal → plugin → PubSub pipeline.

3. **The LLM context and the user display are distinct**. A SQL query may return 10,000 rows; the LLM gets a truncated summary, the user gets full JSON for table rendering.

4. **Per-agent state is the common case**. Most agents maintain their own artifacts. Shared state (use case 3) is a distinct, harder problem.

5. **Phoenix LiveView is the rendering target**. No separate SPA or API layer.

---

## Proposal A: Agent Artifacts via Jido Memory Spaces

### Core Idea

Use Jido's **Memory** primitive (mutable cognitive substrate with named Spaces) as the canonical store for agent "artifacts" — structured data produced by tools that the frontend should render. A new `ArtifactPlugin` replaces/augments the streaming plugin to broadcast artifact changes alongside message signals.

### How It Works

**1. In the tool action**, produce both the LLM return value and an artifact update:

```elixir
defmodule Murmur.Tools.ArxivSearch do
  use Jido.Action,
    name: "arxiv_search",
    schema: Zoi.object(%{query: Zoi.string()})

  def run(params, ctx) do
    papers = ArxivClient.search(params.query)

    # Return value for the LLM (truncated text summary)
    llm_summary = papers |> Enum.take(5) |> Enum.map_join("\n", & &1.title)

    # State update: merge new papers into the :papers memory space
    # The agent kernel applies this to agent.state.__memory__
    {:ok, %{
      __memory__: {:append_space, :papers, papers}
    }, %Directive.Emit{signal: artifact_signal(:papers, papers)}}
  end
end
```

**2. An `ArtifactPlugin`** intercepts artifact signals and broadcasts them:

```elixir
defmodule Murmur.Agents.ArtifactPlugin do
  use Jido.Plugin,
    name: "artifacts",
    state_key: :artifacts,
    actions: [],
    signal_patterns: ["artifact.*"]

  def handle_signal(signal, context) do
    session_id = context.agent.id
    Phoenix.PubSub.broadcast(
      Murmur.PubSub,
      "agent_artifacts:#{session_id}",
      {:artifact_update, session_id, signal.type, signal.data}
    )
    {:ok, :continue}
  end
end
```

**3. LiveView** subscribes to the artifact topic and maintains `@artifacts` as a map of `session_id → %{papers: [...], queries: [...], ...}`:

```elixir
def handle_info({:artifact_update, session_id, "artifact.papers", data}, socket) do
  {:noreply, update_artifact(socket, session_id, :papers, data)}
end
```

**4. Template** renders artifact panes alongside or below the chat:

```heex
<%= if artifact = get_in(@artifacts, [session.id, :papers]) do %>
  <.paper_grid papers={artifact} />
<% end %>
```

### Why Memory Spaces

- Jido Memory already exists as a mutable, revision-tracked, namespaced data store inside agent state
- Memory Spaces have built-in concurrency control (per-space revision counters)
- Memory survives hibernate/thaw via the persistence layer (unlike ad-hoc assigns)
- The agent can reason about its accumulated artifacts via Memory (e.g., "you have found 12 papers so far")
- Clean separation: Thread = what happened, Memory = what the agent currently has

### Tradeoffs

| Pro | Con |
|-----|-----|
| Uses existing Jido primitives (Memory, Signals, Plugins) | Memory API is map/list only — no built-in schema validation for artifact shapes |
| Revision-tracked, survives restarts | Requires a convention for how tools update Memory (not enforced by framework) |
| Agent can read its own artifacts for reasoning | Memory state is inside the agent GenServer — large artifacts (10k SQL rows) sit in process memory |
| Clean separation of LLM context vs. user display | Need to define the artifact signal contract ourselves |
| Simple PubSub pipeline reuses existing pattern | Frontend needs to maintain parallel state (`@artifacts`) alongside `@messages` |

### Shared State Extension (Use Case 3)

For the collaborative document, Memory doesn't natively support cross-agent sharing. Two sub-options:

**A1. External shared Memory via ETS/PG/CRDT**: A separate GenServer owns the shared document state. Each agent's tool calls go through this shared process, which broadcasts updates to all interested parties (agents and LiveView). Agents subscribe to changes via a Sensor or signal cast.

**A2. Shared PubSub topic**: Each agent and the LiveView subscribe to `"workspace:#{wid}:document:#{doc_id}"`. Any edit broadcasts a patch. No single owner — eventual consistency via operational transforms or CRDTs (e.g., using Yjs via a hook or Automerge).

---

## Proposal B: DataStream Protocol (Vercel-inspired)

### Core Idea

Inside any tool action, the code can emit **data events** into a side-channel. These events are not part of the LLM conversation — they flow directly to the frontend via PubSub. No aggregation happens on the backend; the frontend accumulates and renders them.

### How It Works

**1. A `DataStream` context** is injected into tool execution. Tools call `DataStream.emit/3`:

```elixir
defmodule Murmur.Tools.SqlQuery do
  use Jido.Action, name: "sql_query", schema: ...

  def run(params, ctx) do
    {columns, rows} = Database.query(params.sql)

    # Emit full results to the frontend (data event)
    DataStream.emit(ctx, "query_result", %{
      sql: params.sql,
      columns: columns,
      rows: rows  # Full JSON — could be thousands of rows
    })

    # Return truncated summary for the LLM
    summary = rows |> Enum.take(20) |> format_as_text_table(columns)
    {:ok, %{result: summary}}
  end
end
```

**2. `DataStream.emit/3`** creates a Jido Signal and either:
- Emits it as a Directive (if we have access to the action return pipeline)
- Broadcasts directly over PubSub (simpler but breaks the "no side effects in actions" rule)
- Sends it to the owning AgentServer via `send/2`, which then processes it through the plugin pipeline

**3. LiveView** receives data events and accumulates them in a per-session store:

```elixir
def handle_info({:data_event, session_id, "query_result", data}, socket) do
  {:noreply, append_data_event(socket, session_id, "query_result", data)}
end
```

**4. Frontend rendering** is driven by the accumulated data events, with type-specific components.

### Implementation via Existing Primitives

The cleanest way to implement this within Jido is:

- Tool actions return a Directive that emits a custom signal (e.g., `"data.query_result"`)
- The ArtifactPlugin (or a DataStreamPlugin) picks up `"data.*"` signals and broadcasts
- The LiveView has data-event handlers per signal type

This is essentially the same plugin pipeline as Proposal A, but with a different philosophy: **the backend doesn't aggregate — each emission is a standalone event**.

### Tradeoffs

| Pro | Con |
|-----|-----|
| Simple backend — just forward events, no state management | Frontend must handle all accumulation, deduplication, ordering |
| Easy to add new data types (just emit a new event type) | No backend "current state" — if the user refreshes, data events are gone unless separately persisted |
| Familiar to anyone who's used Vercel AI SDK | The agent cannot reason about accumulated data (it doesn't know what's been emitted) |
| Naturally fits streaming/append-only patterns | Shared state (use case 3) doesn't fit the model — you need bidirectional flow |
| Minimal framework changes needed | Large payloads (10k SQL rows) transit PubSub as single messages |

### Shared State Extension (Use Case 3)

The DataStream model is fundamentally unidirectional (agent → frontend). For shared documents, you'd need a completely separate mechanism (same as A1/A2 above). This makes DataStream insufficient as a sole solution for all three use cases.

---

## Proposal C: Hybrid — Agent Artifacts (Memory) + DataStream Events

### Core Idea

Combine the strengths of both approaches:

- **Artifacts** (via Memory Spaces) for structured data that the agent accumulates and can reason about. The Memory is the source of truth; changes are broadcast to the frontend.
- **Data events** (streaming) for ephemeral, high-frequency, or presentational data that doesn't need to be stored in agent state (e.g., progress updates, partial results during long-running operations).

### Architecture

```
┌───────────────────────────────────────────────────────────────────────┐
│ Tool Action                                                           │
│                                                                       │
│  1. Update agent memory:                                              │
│     {:ok, state_changes, directives}                                  │
│     state_changes include Memory space updates                        │
│                                                                       │
│  2. Return Emit directives for:                                       │
│     - "artifact.{type}" signals (carry full current artifact state)   │
│     - "data.{type}" signals (carry ephemeral display data)            │
│                                                                       │
│  3. Return LLM-facing result (may differ from user-facing data)       │
└───────────────────┬───────────────────────────────────────────────────┘
                    │
    ┌───────────────▼───────────────┐
    │ AgentServer processes cmd/2   │
    │  - Applies state changes      │
    │  - Memory spaces updated      │
    │  - Drains directive queue     │
    │    - Emit directives fired    │
    └───────────────┬───────────────┘
                    │ Signals flow through plugin pipeline
    ┌───────────────▼───────────────┐
    │ DataPlugin.handle_signal/2    │
    │  - "artifact.*" → broadcast   │
    │    artifact state snapshot    │
    │  - "data.*" → broadcast       │
    │    ephemeral data event       │
    │  - "ai.*" → existing stream   │
    │    behavior (deltas, etc.)    │
    └───────────────┬───────────────┘
                    │ PubSub
    ┌───────────────▼───────────────┐
    │ LiveView                      │
    │  @artifacts: persistent data  │
    │    loaded from Memory on      │
    │    mount, updated via PubSub  │
    │  @data_events: ephemeral      │
    │    accumulated in LiveView    │
    │  @streaming: existing LLM     │
    │    token streaming            │
    │  @messages: existing chat     │
    └───────────────────────────────┘
```

### Dual-Return Pattern for Tools

The key design innovation: a tool action produces **two representations** of its output.

```elixir
defmodule Murmur.Tools.SqlQuery do
  use Jido.Action, name: "sql_query", schema: ...

  def run(params, ctx) do
    {columns, rows} = Database.query(params.sql)

    # 1. User-facing artifact (full data, stored in Memory)
    artifact = %{
      type: :query_result,
      sql: params.sql,
      columns: columns,
      rows: rows,
      executed_at: DateTime.utc_now()
    }

    # 2. LLM-facing summary (truncated, goes into the tool result message)
    llm_result = %{
      summary: "Query returned #{length(rows)} rows",
      preview: rows |> Enum.take(10) |> format_table(columns),
      columns: columns
    }

    # State update: append to :query_results memory space
    # Directive: emit artifact signal for LiveView
    {:ok, llm_result,
      %Directive.Emit{
        signal: Signal.new!(
          "artifact.query_result",
          artifact,
          source: "/tools/sql_query"
        ),
        dispatch: {:pubsub, topic: "agent_artifacts:#{ctx.agent.id}"}
      }}
  end
end
```

### Shared State (Use Case 3)

For collaborative documents, a dedicated **SharedArtifact GenServer** per document:

```elixir
defmodule Murmur.Artifacts.SharedDocument do
  use GenServer

  # Any agent or the LiveView can propose edits
  def apply_edit(doc_id, edit, author) do
    GenServer.call(via(doc_id), {:edit, edit, author})
  end

  # Returns current document state
  def get(doc_id), do: GenServer.call(via(doc_id), :get)

  def handle_call({:edit, edit, author}, _from, state) do
    new_state = apply_ot(state, edit)
    broadcast_change(state.id, edit, author)
    {:reply, :ok, new_state}
  end
end
```

- Agents interact via a `SharedDocumentTool` action that calls `SharedDocument.apply_edit/3`
- The LiveView subscribes to `"shared_document:#{doc_id}"` and renders the live document
- Human edits go through LiveView events → `SharedDocument.apply_edit/3`
- All parties (agents + human) see the same state through PubSub broadcasts

This is a natural extension of the artifact pattern, where the "artifact" is a shared process rather than agent-local memory.

### Tradeoffs

| Pro | Con |
|-----|-----|
| Best of both worlds: persistent artifacts + ephemeral events | More concepts for developers to learn (artifacts vs. data events) |
| Agent can reason about its artifacts via Memory | Slightly more complex plugin pipeline |
| Artifacts survive hibernate/thaw and page refresh | Need to define clear conventions for when to use which channel |
| Shared state handled as a natural extension | SharedDocument GenServer is additional infrastructure |
| Clean separation: what the LLM sees vs. what the user sees | Memory spaces hold data in agent process memory |
| Fully within Jido's primitive set | |

---

## Proposal D: LangGraph-style Reducer State

### Core Idea

Each agent has a typed state graph. Tool executions produce state updates that are merged via configurable **reducer functions**. The entire agent state (not just messages) is projected to the frontend. Shared state between agents is modeled as a shared graph node.

### How It Would Work

```elixir
defmodule Murmur.Agents.ArxivAgent do
  use Jido.Agent,
    name: "arxiv_agent",
    schema: Zoi.object(%{
      papers: Zoi.list(Zoi.any()) |> Zoi.default([]),
      current_pdf: Zoi.any() |> Zoi.optional(),
      messages: Zoi.list(Zoi.any()) |> Zoi.default([])
    }),
    reducers: %{
      papers: :append,        # new papers are appended to existing
      current_pdf: :replace,  # latest PDF replaces previous
      messages: :append       # messages accumulate
    }
```

Each tool returns a partial state map. The reducers merge it into the agent's state:

```elixir
def run(params, _ctx) do
  papers = ArxivClient.search(params.query)
  {:ok, %{papers: papers}}  # reducer will append these to existing papers
end
```

### Why This Doesn't Fit

Jido already has its own state model. An agent is an immutable struct with a `state` map validated by a Zoi schema. The state is updated through `cmd/2` which returns the complete new agent. There are no "reducers" — the action's return value IS the new state.

Implementing LangGraph-style reducers would require:
1. Overriding Jido's state merge behavior (currently a simple `Map.merge`)
2. Adding a custom strategy that intercepts action results and applies per-field reducers
3. Building a state diff mechanism to broadcast only changes

This is fighting the framework rather than working with it. Jido's Memory primitive already provides namespaced mutable state with revision tracking, which accomplishes the same goal more naturally.

### Tradeoffs

| Pro | Con |
|-----|-----|
| Familiar to LangGraph users | Requires overriding core Jido state merge behavior |
| Elegant per-field merge semantics | Schema + reducers is a lot of ceremony per agent |
| State is always consistent and typed | Fighting the framework — Jido isn't designed for this |
| Built-in diff detection via schema comparison | Shared state across agents needs a separate mechanism anyway |
| | Overkill for simple cases (most tools don't need reducers) |

---

## Comparison Matrix

| Dimension | A: Memory Spaces | B: DataStream | C: Hybrid | D: Reducers |
|-----------|-----------------|---------------|-----------|------------|
| **Jido alignment** | Excellent — uses existing Memory primitive | Good — uses Signals + Plugins | Excellent — uses Memory + Signals | Poor — overrides state merge |
| **Agent can reason about data** | Yes (reads own Memory) | No (data is fire-and-forget) | Yes (artifacts in Memory) | Yes (in agent state) |
| **Survives refresh/restart** | Yes (Memory persists via hibernate) | No (ephemeral) | Artifacts yes, events no | Yes (state persists) |
| **LLM vs. user display separation** | Manual (tool returns both) | Natural (emit is separate) | Natural (dual-return pattern) | Manual (projection function) |
| **Shared state support** | Needs extension (A1/A2) | Doesn't fit the model | Natural extension (SharedArtifact) | Needs extension |
| **Implementation complexity** | Low-Medium | Low | Medium | High |
| **Frontend complexity** | Medium (maintain @artifacts) | Medium (accumulate events) | Medium-High (both) | Medium (render state) |
| **Framework changes needed** | Convention for Memory updates in tools | Custom signal types | Custom signal types + SharedArtifact | Custom strategy + reducer system |
| **Scalability (large data)** | Data sits in agent process | Data transits PubSub once | Artifacts in process, events transit | Data sits in agent process |

---

## Recommendation: Proposal C (Hybrid)

### Why

1. **It's the only proposal that naturally addresses all three use cases** — single-agent artifacts, dual LLM/user representations, and shared documents — within a coherent model.

2. **It works with Jido, not against it.** Memory Spaces are a first-class Jido primitive designed for exactly this kind of mutable agent state. Signals and Plugins are the designed interception/broadcast mechanism. No framework overrides needed.

3. **The dual-return pattern solves the LLM vs. user display problem cleanly.** A tool action returns `{:ok, llm_result, directives}` where:
   - `llm_result` becomes the tool result message in the LLM conversation (can be truncated)
   - Directives include artifact emissions that carry the full user-facing data
   - These are separate concerns with separate delivery paths

4. **Artifacts are persistent and introspectable.** Unlike pure DataStream events, artifacts in Memory survive page refresh and agent hibernate/thaw. The agent can also inspect its own artifacts for reasoning ("I've found 12 papers matching your query so far...").

5. **Shared state is a natural extension**, not a bolt-on. The SharedArtifact GenServer follows the same pattern (tool → emit → broadcast → render) but with a shared process as the state owner instead of agent Memory.

6. **Incremental adoption.** We can start with just the artifact plugin (handles use cases 1 and 2), validate the approach, and add SharedArtifact later when use case 3 becomes priority.

### Phased Implementation Plan

**Phase 1: Artifact Foundation**
- Define `Murmur.Agents.ArtifactPlugin` (extends existing streaming plugin pattern)
- Define artifact signal types: `"artifact.created"`, `"artifact.updated"`, `"artifact.cleared"`
- Convention for tool actions to return dual representations
- LiveView subscribes to artifact topic, maintains `@artifacts` assign
- Add artifact rendering components (generic "artifact pane" that dispatches to type-specific renderers)

**Phase 2: Concrete Artifact Types**
- `PaperListArtifact` — for arxiv agent (card grid + iframe viewer)
- `QueryResultArtifact` — for SQL agent (table component + SQL display)
- `MarkdownArtifact` — for writer/review agent (rich text display)
- Each type has a component + optional interactivity (click-to-expand, sort, filter)

**Phase 3: Shared Artifacts**
- `Murmur.Artifacts.SharedDocument` GenServer for collaborative editing
- `SharedDocumentTool` action for agents
- LiveView integration for human editing
- PubSub-based sync between all parties

**Phase 4: Ephemeral Data Events (if needed)**
- `"data.*"` signal type for progress updates, partial results
- Useful for long-running operations where you want to show intermediate state
- Can be added without disrupting the artifact layer

### Key Design Decisions

1. **Artifact naming convention**: Artifact names use snake_case identifiers scoped to the tool domain (e.g., `"papers"`, `"query_results"`, `"document"`). No prefix is needed since artifacts live in their own assign (`@artifacts`) separate from Memory spaces.

2. **Artifact signal payload**: Snapshot for initial load, deltas for updates. Signals carry `mode: :replace | :append` — the LiveView maintains the full accumulated state and applies the mode. On page refresh, artifacts are currently lost (they live only in the LiveView process). Future: reload from agent Memory on mount.

3. **Large artifact handling**: **TODO (future)** — For now we assume artifacts fit comfortably in process memory. When SQL results or document collections grow large, implement a reference-based approach: store large results in ETS or an LRU cache and pass a reference in the artifact signal.

4. **Frontend component architecture**: Function components for static display (lists, tables, JSON). JS hooks (via `phx-hook`) for interactive elements (PDF viewer, sortable tables, collaborative editor). Phase 1 provides a generic artifact renderer; Phase 2 will add type-specific components.

5. **Artifact lifecycle**: **TODO (future)** — For now, artifacts accumulate indefinitely for the lifetime of the LiveView process. They are cleared when the user clears the team or removes an agent. Future options: explicit clear action, TTL-based expiry, or user-managed cleanup.
