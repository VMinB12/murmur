# Contract: JidoArtifacts Public API

**Package**: `jido_artifacts`  
**Version**: 0.1.0

## Module: `JidoArtifacts.Artifact`

### `emit/4`

Creates an `%Directive.Emit{}` for broadcasting artifact data through the plugin system.

```elixir
@spec emit(ctx :: map(), name :: String.t(), data :: term(), opts :: keyword()) :: Directive.Emit.t()

# Options:
#   merge: (existing :: term(), new :: term()) -> merged :: term()  (optional)
#   scope: :agent | :workspace  (default: :agent)
```

**Signal data produced**:
```elixir
%{
  name: String.t(),
  data: term(),
  mode: :replace | :merge,
  merge_result: term() | nil,  # present only when merge: is provided
  scope: :agent | :workspace
}
```

### `artifact_topic/1`

Returns the PubSub topic for artifact updates.

```elixir
@spec artifact_topic(session_id :: String.t()) :: String.t()
# Returns: "jido_artifacts:#{session_id}"
```

---

## Module: `JidoArtifacts.Merge`

### Built-in merge helpers

```elixir
@spec append(existing :: term(), new :: term()) :: list()
@spec prepend(existing :: term(), new :: term()) :: list()
@spec append_max(max :: pos_integer()) :: (term(), term() -> list())
@spec prepend_max(max :: pos_integer()) :: (term(), term() -> list())
@spec upsert_by(key_fn :: (term() -> term())) :: (term(), term() -> list())
```

---

## Module: `JidoArtifacts.ArtifactPlugin`

### Plugin Contract

```elixir
use Jido.Plugin,
  name: "artifacts",
  signal_patterns: ["artifact.*"]

# handle_signal/2 behavior:
# 1. Broadcasts artifact update via PubSub
# 2. Returns {:ok, {:override, {StoreArtifact, params}}}
```

---

## Module: `JidoArtifacts.Actions.StoreArtifact`

### Action Contract

```elixir
use Jido.Action,
  name: "store_artifact",
  schema: [
    artifact_name: [type: :string, required: true],
    artifact_data: [type: :any, required: true],
    artifact_mode: [type: :atom, default: :replace]
  ]

# run/2 behavior:
# - Wraps data in ArtifactEnvelope
# - Stores in agent.state.artifacts[name]
# - Increments version on update
# - Deletes key when merge_result is nil
# Returns: {:ok, %{artifacts: updated_map}}
```

---

## Application Configuration

```elixir
config :jido_artifacts,
  pubsub: MyApp.PubSub  # Required — module implementing Phoenix.PubSub
```

## Dependencies

```elixir
{:jido, "~> 2.0"},
{:jido_signal, "~> 2.0"},
{:jido_action, "~> 2.0"},
{:phoenix_pubsub, "~> 2.0"},
{:jason, "~> 1.0"}
```
