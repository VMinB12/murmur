# Artifact Design Philosophy

**Date**: 2026-03-31
**Status**: Living document

## Overview

Artifacts are the mechanism by which agents expose structured data to the user interface beyond the conversation history. The conversation column shows chat messages and tool call summaries. The data panel shows artifacts — rich, interactive data views managed by the agent.

This document captures the design principles and patterns that guide artifact usage across all agents.

## Core Principle: Backend Owns State, Frontend Displays It

The frontend receives two things from the backend:

1. **Conversation history** (ThreadEntry) → drives the chat column
2. **Artifacts** (StoreArtifact → agent state → checkpoint) → drives the data panel

The frontend never derives data panel content by parsing conversation history. The backend decides what data to expose; the frontend renders it. This keeps the frontend simple and the data flow unidirectional.

## Two Persistence Layers

| Layer | Storage | Drives | Purpose |
|-------|---------|--------|---------|
| **ThreadEntry** | `jido_murmur_thread_entries` (JSONB payload) | Chat column | Conversation timeline: user messages, assistant responses, tool calls, tool results |
| **Artifacts** | `StoreArtifact` → `agent.state[:artifacts]` → `jido_murmur_checkpoints` | Data panel | Agent-managed structured data: search results, query tabs, visualizations, documents |

Both survive server restarts. ThreadEntry is immutable (append-only timeline). Artifacts are mutable (versioned, with merge strategies).

## Artifact Flavors: Materialized vs. Deferred

All artifacts use the same pipeline: `Artifact.emit` → `ArtifactPlugin` → PubSub broadcast + `StoreArtifact` → agent state → checkpoint. The difference is what data the artifact contains and how the renderer handles it.

### Materialized Artifacts

The artifact stores the full result data. The renderer displays it directly.

**When to use**: The result data is small enough to store, and you don't want to re-fetch it (external APIs, expensive computations, data that changes over time and you want a snapshot).

**Example**: ArXiv agent's `"papers"` artifact stores full paper metadata (title, abstract, authors, PDF URL). The renderer displays the list directly from artifact data. On revisit, papers appear immediately without re-querying the ArXiv API.

```
Tool executes → fetches data → Artifact.emit(ctx, "papers", paper_data, mode: :merge)
                                 ↓
                   StoreArtifact stores full paper data in agent state
                                 ↓
                   Renderer displays paper list directly from artifact data
                                 ↓
                   On revisit: data restored from checkpoint → immediate display
```

### Deferred Artifacts

The artifact stores only a reference (e.g., a query, an ID, a URL). The renderer fetches results dynamically when the user views the tab.

**When to use**: The result data is too large to store, the data should always reflect the current state (not a snapshot), or re-fetching is cheap and desirable.

**Example**: SQL agent's `"sql_results"` artifact stores only SQL query text and a label. The renderer executes the SQL on demand when the user views the tab. On revisit, tabs show "Click to load" placeholders.

```
Tool executes → validates SQL → Artifact.emit(ctx, "sql_results", %{sql, label}, mode: :merge)
                                  ↓
                    StoreArtifact stores SQL text only in agent state
                                  ↓
                    Renderer receives signal → executes SQL → displays paginated table
                                  ↓
                    On revisit: data restored from checkpoint → placeholder → click to re-execute
```

### Choosing Between Them

| Question | Materialized | Deferred |
|----------|-------------|----------|
| Is the result data small (< ~100KB)? | ✅ Store it | Either works |
| Is the result data potentially large? | ❌ Don't store | ✅ Store only reference |
| Should results reflect current state? | ❌ Shows snapshot | ✅ Re-fetches latest |
| Is re-fetching expensive? | ✅ Store to avoid re-fetch | ❌ Only if cheap to re-fetch |
| Is the external source unreliable? | ✅ Store while you have it | ❌ Risky if source goes down |

Most agents should default to **materialized** artifacts. Use deferred only when there's a clear reason not to store the result data.

## Artifact Merge Strategies

Artifacts support two modes:

- **`:replace`** — Overwrites the entire artifact. Use for single-value artifacts (e.g., "currently displayed paper").
- **`:merge`** — Applies a merge function to combine new data with existing data. Use for collections.

Available merge functions (from `JidoArtifacts.Merge`):
- `append` — Add to end of list
- `prepend` — Add to beginning of list
- `append_max` — Append with a maximum list size (oldest items evicted)
- `prepend_max` — Prepend with a maximum list size
- `upsert_by` — Update existing item by key or append if new

### Pattern: One Artifact Tab, Multiple Entries

For agents that produce multiple results (SQL queries, search results), use a single artifact name with `:merge` mode. The renderer shows sub-tabs or a list within one data panel tab.

```elixir
# Each display call appends to the list
Artifact.emit(ctx, "sql_results", %{sql: query, label: label},
  mode: :merge, merge: {:append, :data})
```

This keeps the data panel clean (one "SQL Queries" tab) while supporting multiple queries within it.

## Renderer Responsibilities

Each artifact type has a registered renderer with two views:

- **`badge/1`** — Compact view shown in the data panel tab bar (e.g., "SQL Queries (3)")
- **`detail/1`** — Full view shown when the tab is selected

For **materialized artifacts**, the renderer displays data directly from the artifact assigns.

For **deferred artifacts**, the renderer is responsible for:
1. Showing a loading/placeholder state
2. Fetching data (via LiveView event → server-side execution → assign update)
3. Rendering the fetched data
4. Handling fetch errors gracefully

## Data Flow Summary

```
                    REAL-TIME (during conversation)
                    ───────────────────────────────
Tool call
  ├── ThreadEntry ← tool call + result stored automatically (chat column)
  └── Artifact.emit()
        ├── PubSub broadcast → LiveView → data panel tab updates in real-time
        └── StoreArtifact → agent.state[:artifacts] → hibernate → checkpoint

                    ON REVISIT (past conversation)
                    ──────────────────────────────
Mount
  ├── ThreadEntry loaded → UITurn.project_entries() → chat column rendered
  └── Artifacts restored from checkpoint → data panel tabs rendered
        ├── Materialized: data displayed immediately
        └── Deferred: placeholder shown, data fetched on interaction
```

## Guidelines for Agent Developers

1. **Always use `Artifact.emit`** for data panel content. Never broadcast raw PubSub messages.
2. **Choose materialized by default**. Only use deferred when result data is too large or must be fresh.
3. **Use `:merge` mode for collections**. One artifact name, multiple entries. Don't create separate artifact names per item.
4. **Keep artifact data serializable**. It must survive Erlang term serialization → JSONB → thaw. Avoid PIDs, refs, or anonymous functions.
5. **Register a renderer** for your artifact type. The generic fallback works but provides a poor user experience.
6. **Include metadata** in artifact entries (labels, counts, timestamps) so renderers can show useful badges and tab labels without fetching full data.
