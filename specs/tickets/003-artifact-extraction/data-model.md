# Data Model: Artifact System Extraction

**Feature Branch**: `003-artifact-extraction`  
**Date**: 2026-03-29

## Entities

### Artifact (Logical — in-memory state, not Ecto)

The named unit of structured data produced by tool actions and stored in agent state.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `String.t()` | Unique identifier within agent scope (e.g., `"papers"`, `"displayed_paper"`) |
| `data` | `term()` | The raw artifact data (list, map, struct — any term) |

**Storage location**: `agent.state.artifacts[name]` — wrapped in `ArtifactEnvelope`

---

### ArtifactEnvelope (Logical — stored in agent state)

Metadata wrapper around artifact data. Created/updated by `StoreArtifact`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `data` | `term()` | — | The raw artifact data |
| `updated_at` | `DateTime.t()` | `DateTime.utc_now()` | Timestamp of last update |
| `source` | `String.t()` | agent ID | Which agent/action produced this version |
| `version` | `pos_integer()` | `1` | Monotonically incrementing version counter |

**Structure**: Plain map `%{data: ..., updated_at: ..., source: ..., version: ...}`  
**Not an Ecto schema** — lives in agent state (ETS/memory), persisted via Jido checkpoint.

**State transitions**:
- **Create**: `version: 1`, `updated_at: now`, `source: agent_id`
- **Update**: `version: prev + 1`, `updated_at: now`, data replaced or merged
- **Delete**: When merge result is `nil`, the entire key is removed from `artifacts` map

---

### ArtifactSignal (Wire format — Jido.Signal struct)

Signal emitted by `Artifact.emit/4`, routed through plugin system.

| Field | Type | Description |
|-------|------|-------------|
| `type` | `String.t()` | `"artifact.#{name}"` |
| `source` | `String.t()` | `"/jido_artifacts/#{name}"` |
| `subject` | `String.t() \| nil` | `"/agents/#{agent_id}"` or `nil` |
| `id` | `String.t()` | UUID7 (auto-generated) |
| `time` | `String.t()` | ISO 8601 timestamp (auto-generated) |
| `data.name` | `String.t()` | Artifact name |
| `data.data` | `term()` | Raw artifact data from tool |
| `data.mode` | `atom()` | `:replace` (when no merge) |
| `data.merge_result` | `term() \| nil` | Pre-computed merged result (when merge provided) |
| `data.scope` | `atom()` | `:agent` (default) or `:workspace` (reserved) |

---

### Merge Functions (Module: `JidoArtifacts.Merge`)

Built-in merge helpers. All accept `(existing :: term(), new :: term()) -> merged :: term()`.

| Helper | Signature | Behavior |
|--------|-----------|----------|
| `append/2` | `fn(existing, new)` | `(existing \|\| []) ++ List.wrap(new)` |
| `prepend/2` | `fn(existing, new)` | `List.wrap(new) ++ (existing \|\| [])` |
| `append_max/1` | `fn(max) -> fn(existing, new)` | Appends then takes last `max` items |
| `prepend_max/1` | `fn(max) -> fn(existing, new)` | Prepends then takes first `max` items |
| `upsert_by/1` | `fn(key_fn) -> fn(existing, new)` | Merges lists by key, new items replace matching |

---

## Relationships

```
Tool Action
  │ calls Artifact.emit/4
  ▼
ArtifactSignal (%Jido.Signal{type: "artifact.*"})
  │ intercepted by
  ▼
ArtifactPlugin
  │ broadcasts via PubSub → LiveView
  │ overrides to StoreArtifact
  ▼
StoreArtifact
  │ wraps in ArtifactEnvelope
  │ stores in agent.state.artifacts
  ▼
ArtifactPanel (jido_murmur_web)
  │ unwraps envelope
  │ dispatches to renderer
  ▼
Renderer Component (PaperList, PdfViewer, Generic)
```

## Validation Rules

- `name` must be a non-empty string
- `scope` must be `:agent` or `:workspace` (`:workspace` raises/warns at plugin level)
- `merge` function, when provided, must be a 2-arity function
- `version` starts at 1 and is monotonically increasing
- `updated_at` must be a UTC DateTime
