# Research: Artifact System Extraction

**Feature Branch**: `003-artifact-extraction`  
**Date**: 2026-03-29

## Research Tasks

### R1: Current Artifact API Surface & Extraction Boundary

**Context**: Need to determine exact modules, functions, and dependencies that must move to `jido_artifacts`.

**Finding**: Three core modules exist:
- `JidoMurmur.Artifact` — `emit/4`, `artifact_topic/1`
- `JidoMurmur.ArtifactPlugin` — `handle_signal/2` plugin using `Jido.Plugin`
- `JidoMurmur.Actions.StoreArtifact` — `run/2` action using `Jido.Action`

**Decision**: Extract all three into `jido_artifacts` package under these namespaces:
- `JidoArtifacts` (top-level, config accessors)
- `JidoArtifacts.Artifact` (emit API)
- `JidoArtifacts.ArtifactPlugin` (plugin)
- `JidoArtifacts.Actions.StoreArtifact` (action)
- `JidoArtifacts.Merge` (new — merge helpers)

**Rationale**: Clean namespace that follows Jido ecosystem conventions (`JidoTasks`, `JidoAI`, etc.). Keeps the plugin pattern intact.

**Alternatives Considered**:
- Keeping artifact code in jido_murmur and only exporting a thin wrapper → rejected because jido_arxiv still depends on full jido_murmur
- Merging into jido_action → rejected because artifacts have PubSub and state concerns beyond pure actions

### R2: Merge Callback Design Patterns

**Context**: Current system only supports `:replace` and `:append` modes via atom flag. Spec requires extensible merge callbacks.

**Finding**: Current `StoreArtifact` uses a simple case statement:
```elixir
case mode do
  :append -> existing ++ List.wrap(data)
  _replace -> data
end
```

**Decision**: Replace mode-based dispatch with function-based merge strategy:
- `emit/4` accepts `merge: fn(existing, new) -> merged` keyword
- When merge is provided, apply eagerly at emit-time using agent state from context
- Include `merge_result` in signal data so `StoreArtifact` stores the pre-merged result
- Ship built-in helpers in `JidoArtifacts.Merge`: `append/2`, `prepend/2`, `append_max/1`, `prepend_max/1`, `upsert_by/1`

**Rationale**: Function callbacks are more flexible than growing an atom enum. Eager merge at emit-time means the merge function runs in the tool's process, not the agent process — better isolation.

**Alternatives Considered**:
- Lazy merge in `StoreArtifact` — rejected because the merge function may need tool-specific logic not available in the agent process
- Protocol-based merge — rejected because a simple function callback is sufficient and avoids protocol dispatch overhead

### R3: Metadata Envelope Design

**Context**: Currently artifacts are stored as raw data in `agent.state.artifacts`. Need to add versioning, timestamps, and source tracking.

**Finding**: Agent state structure is `%{artifacts: %{name => data}}`. This map is persisted via Jido's checkpoint system.

**Decision**: Wrap stored artifacts in envelope: `%{data: term(), updated_at: DateTime.t(), source: String.t(), version: integer()}`. `StoreArtifact` constructs this envelope. The envelope is opaque to tool authors — they emit raw data, the system adds metadata.

**Rationale**: Envelope at storage layer keeps the emit API simple while adding observability. Version counter enables change detection. Source enables multi-agent tracing.

**Alternatives Considered**:
- Adding metadata fields to the signal instead of storage → rejected because signals are ephemeral; metadata should persist with the artifact
- Using an Ecto schema for metadata → rejected because artifacts live in agent state (ETS/memory), not the database

### R4: CloudEvents Source/Subject Patterns

**Context**: Spec requires signals to carry CloudEvents `source` and `subject` fields.

**Finding**: `Jido.Signal` struct has both `source` (required) and `subject` (optional) fields per CloudEvents spec. Current artifact signals set `source: "/artifact/#{name}"` but don't set `subject`.

**Decision**: 
- `source`: `/jido_artifacts/#{name}` (namespace under package, not generic `/artifact/`)
- `subject`: `/agents/#{agent_id}` extracted from `ctx[:state][:__agent_id__]` if available, `nil` otherwise
- Graceful degradation: no crash when agent identity is missing

**Rationale**: Follows CloudEvents URI conventions. Source identifies the event producer component. Subject identifies the entity the event relates to.

### R5: Package Dependency Minimization

**Context**: Extracted `jido_artifacts` must depend only on core Jido packages, not on `jido_murmur`.

**Finding**: Current dependencies used by artifact modules:
- `Jido.Signal` (from `:jido_signal`)
- `Jido.Agent.Directive.Emit` (from `:jido`) 
- `Jido.Plugin` (from `:jido`)
- `Jido.Action` (from `:jido_action`)
- `Phoenix.PubSub` (from `:phoenix_pubsub`)

**Decision**: `jido_artifacts` deps: `{:jido, "~> 2.0"}, {:jido_signal, "~> 2.0"}, {:jido_action, "~> 2.0"}, {:phoenix_pubsub, "~> 2.0"}, {:jason, "~> 1.0"}`. No jido_murmur, no jido_ai, no ecto.

**Rationale**: These are the minimum deps needed. `:jido` provides Plugin behaviour and Directive.Emit. `:jido_action` provides Action behaviour. `:jido_signal` provides Signal struct. `:phoenix_pubsub` is needed for broadcasts. `:jason` for serialization.

### R6: ArtifactPanel Envelope Unwrapping

**Context**: When metadata envelope is added, existing renderers must not break.

**Finding**: `ArtifactPanel` in jido_murmur_web passes artifact data directly to renderer components via assigns. Renderers expect raw data (list of papers, single paper struct, etc.).

**Decision**: Add unwrap logic in `ArtifactPanel` dispatcher: if data is a map with `:data` key and `:version` key (envelope signature), extract `.data`. Otherwise pass through unchanged. This handles both old and new format during migration.

**Rationale**: Single-point unwrap in the dispatcher, transparent to all renderers. Feature-detection (checking for envelope keys) is more robust than version flag.

### R7: PubSub Configuration for Extracted Package

**Context**: `ArtifactPlugin` currently calls `JidoMurmur.pubsub()` which reads from `:jido_murmur` app config. Extracted package needs its own config.

**Decision**: `JidoArtifacts` will provide `pubsub/0` accessor that reads from `:jido_artifacts` app config. The install command / Igniter task will be responsible for setting `config :jido_artifacts, pubsub: MyApp.PubSub`. Fallback: if not configured, attempt to read from `:jido_murmur` config for backward compatibility during migration.

**Rationale**: Each package owns its config. Fallback eases migration for existing users.
