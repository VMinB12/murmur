# Quickstart: Artifact System Extraction

**Feature Branch**: `003-artifact-extraction`

## What Changed

The artifact system (`Artifact`, `ArtifactPlugin`, `StoreArtifact`) is extracted from `jido_murmur` into a standalone `jido_artifacts` package. The API is enhanced with:
- **Merge callbacks**: Custom `fn(existing, new) -> merged` strategies
- **Metadata envelope**: Every stored artifact now includes `updated_at`, `source`, and `version`
- **CloudEvents fields**: Signals carry `source` and `subject` for tracing

## For Tool Authors (e.g., jido_arxiv)

### Before (jido_murmur dependency)
```elixir
# mix.exs
{:jido_murmur, path: "../jido_murmur"}

# In tool action
alias JidoMurmur.Artifact
Artifact.emit(ctx, "papers", papers, mode: :append)
```

### After (jido_artifacts dependency)
```elixir
# mix.exs
{:jido_artifacts, path: "../jido_artifacts"}

# In tool action
alias JidoArtifacts.Artifact
alias JidoArtifacts.Merge

# Replace behavior (default)
Artifact.emit(ctx, "displayed_paper", paper)

# Append with merge callback
Artifact.emit(ctx, "papers", new_papers, merge: &Merge.append/2)

# Bounded append (keep latest 50)
Artifact.emit(ctx, "papers", new_papers, merge: Merge.append_max(50))

# Custom merge
Artifact.emit(ctx, "papers", new_papers, merge: fn existing, new ->
  (existing || []) ++ new |> Enum.uniq_by(& &1.id)
end)
```

## For App Developers (e.g., murmur_demo)

### Configuration
```elixir
# config/config.exs
config :jido_artifacts,
  pubsub: MyApp.PubSub
```

### ArtifactPanel Renderers

No changes needed. The `ArtifactPanel` component automatically unwraps the metadata envelope — renderers continue to receive raw data.

## Migration Path

1. Add `{:jido_artifacts, path: "../jido_artifacts"}` to your mix.exs
2. Replace `JidoMurmur.Artifact` → `JidoArtifacts.Artifact` in tool actions
3. Replace `JidoMurmur.ArtifactPlugin` → `JidoArtifacts.ArtifactPlugin` in agent profiles
4. Add `config :jido_artifacts, pubsub: MyApp.PubSub` to config
5. Replace `:mode` option with `:merge` callback where needed
