# jido_artifacts — Artifact System

## Purpose

Structured artifact emission and management system for Jido agents. Enables tool actions to emit rich, typed data (search results, tables, documents) that are broadcast to the UI, stored in agent state for persistence, and managed with composable merge semantics.

## Public API

| Module | Purpose | Key Function |
|--------|---------|--------------|
| `JidoArtifacts.Artifact` | Signal creation for artifact emission | `emit/4` |
| `JidoArtifacts.Merge` | Composable merge strategies | `append/2`, `prepend/2`, `append_max/1`, `prepend_max/1`, `upsert_by/1` |
| `JidoArtifacts.ArtifactPlugin` | Jido Plugin (auto-registered) | Handles `artifact.*` signals |

### Usage Pattern

```elixir
alias JidoArtifacts.{Artifact, Merge}

def run(params, ctx) do
  results = fetch_data(params)
  {:ok, %{result: summary},
    Artifact.emit(ctx, "results", results, merge: &Merge.append/2)}
end
```

## Internal Architecture

```
Tool Action calls Artifact.emit(ctx, name, data, opts)
    ↓ Creates Jido.Signal with type "artifact.<name>"
ArtifactPlugin.handle_signal/2
    ↓
    ├── Broadcasts via Phoenix.PubSub → LiveView
    └── Overrides routing → StoreArtifact action
          ↓
          Wraps data in metadata envelope
          Stores in agent.state.artifacts[name]
          Increments version counter
          ↓
          Agent state persisted → Survives hibernate/thaw
```

### Key Design Decisions

- **Plugin-based**: Intercepts `artifact.*` signals without explicit route registration
- **Eager merge**: Merge functions run at emit-time to capture context-specific state
- **Action override**: Plugin uses `:override` return to redirect to `StoreArtifact`
- **Metadata envelope**: Wrapped in `{data, updated_at, source, version}` for provenance
- **Dual broadcast**: Signal sent to PubSub and stored in agent state simultaneously

## Data Models

### Artifact Envelope (stored in `agent.state.artifacts[name]`)

```elixir
%{
  data: term(),
  updated_at: DateTime.t(),
  source: String.t(),        # agent ID
  version: non_neg_integer()
}
```

### Signal Data

```elixir
%{
  name: String.t(),
  data: term(),
  mode: :replace | :merge,
  merge_result: term() | nil,
  scope: :agent | :workspace   # :workspace reserved for future
}
```

## Merge Strategies

| Strategy | Purpose |
|----------|---------|
| `append/2` | Add items to end of list |
| `prepend/2` | Add items to start of list |
| `append_max(n)` | Keep last N items |
| `prepend_max(n)` | Keep first N items |
| `upsert_by(key_fn)` | Replace matching items by key, append new |

## Dependencies

**Requires:** `jido ~> 2.0`, `jido_signal ~> 2.0`, `jido_action ~> 2.0`, `phoenix_pubsub ~> 2.0`, `jason ~> 1.0`

**Used by:** `jido_murmur` (plugin registration), `jido_arxiv` (paper artifacts), `jido_sql` (query result artifacts), `murmur_demo`

## Configuration

```elixir
config :jido_artifacts,
  pubsub: MyApp.PubSub
```
