# Artifact Persistence: Analysis & Recommendations

## Problem

Artifacts (structured data produced by agent tools — paper lists, PDF viewers, etc.) are lost on page refresh and server restart. Users must re-trigger tool calls to regenerate them.

## Current Architecture

### Data flow

```
Tool action (e.g. ArxivSearch)
  → Artifact.emit/4 returns a Jido Emit directive
    → AgentServer drains the directive, emitting a signal
      → ArtifactPlugin.handle_signal/2 intercepts "artifact.*" signals
        → PubSub broadcast {:artifact_update, session_id, name, data, mode}
          → WorkspaceLive.handle_info receives it
            → Updates @artifacts assign (in-process LiveView state)
```

### Where artifacts live today

| Layer | Storage | Survives refresh? | Survives restart? |
|-------|---------|-------------------|-------------------|
| `@artifacts` assign in WorkspaceLive | LiveView process memory | No | No |
| ArtifactPlugin state_key `:artifacts` | Agent GenServer state | No (only default `%{}`) | No |
| PubSub broadcast | Ephemeral message | No | No |

The plugin never writes artifact data into the agent's state map. It only broadcasts via PubSub and returns a Noop override. The LiveView accumulates artifacts in `@artifacts` — a plain map assign that is initialized empty on every mount:

```elixir
# workspace_live.ex mount/3
|> assign(:artifacts, Map.new(agent_sessions, &{&1.id, %{}}))
```

### What IS persisted (for comparison)

Messages/conversation history survives both refresh and restart through:

1. **Thread entries** → `jido_thread_entries` table (individual rows per message)
2. **Agent checkpoints** → `jido_checkpoints` table (full agent state snapshot as JSONB)
3. On mount, `load_messages_for_session/1` loads from in-memory agent state or falls back to Ecto storage via `thaw`

Artifacts have **no equivalent persistence path**.

## Options

### Option A: Store artifacts in agent state (plugin-level)

**Approach**: Modify `ArtifactPlugin.handle_signal/2` to accumulate artifact data in the agent's state under the `:artifacts` key (which is already the plugin's `state_key`). Since agent state is checkpointed via `hibernate/1` after every LLM turn, artifacts would be persisted automatically. On mount, the LiveView would read artifacts from the agent's restored state.

**Changes required**:
- `ArtifactPlugin.handle_signal/2` — return `{:ok, state_update}` instead of Noop override so the plugin framework merges artifact data into agent state
- `WorkspaceLive.mount/3` — after loading agent state via `load_messages_for_session`, also extract `agent.state.artifacts` and populate `@artifacts`
- May need to verify that `Jido.Plugin` supports state mutation from `handle_signal/2` (check the Jido plugin API)

**Pros**:
- Minimal new code; rides existing checkpoint/hibernate infrastructure
- No new DB tables or migrations
- Artifacts are automatically cleaned up with agent session deletion (checkpoint cleanup already exists)
- Already serialization-safe: checkpoint uses `:erlang.term_to_binary`

**Cons**:
- Couples artifact lifecycle to agent checkpoint cycle — artifacts only persist after the next `hibernate` call (end of LLM turn), not immediately on emit
- Checkpoint JSONB payload grows with artifact data (paper lists can be large)
- If the Jido plugin `handle_signal` API doesn't support state mutation + override routing simultaneously, may need a two-step approach (state update + separate Noop routing)
- Artifacts from cancelled/failed requests may not persist if `hibernate` isn't called

**Effort**: Small — likely a few hours.

### Option B: Persist artifacts to a dedicated DB table

**Approach**: Create an `artifacts` Ecto schema and table. Write to it when the ArtifactPlugin broadcasts. On mount, load artifacts from the DB.

**Schema**:
```elixir
# jido_artifacts table
:id          - binary_id (PK)
:session_id  - string (FK-like to agent_sessions, indexed)
:name        - string ("papers", "displayed_paper", etc.)
:data        - map (JSONB)
:mode        - string ("replace" | "append")
:inserted_at - utc_datetime_usec
:updated_at  - utc_datetime_usec
```

**Changes required**:
- New migration for `jido_artifacts` table
- New `Murmur.Storage.Artifact` Ecto schema
- New context functions: `upsert_artifact/4`, `list_artifacts_for_session/1`, `delete_artifacts_for_session/1`
- `ArtifactPlugin.handle_signal/2` — call the context to persist before broadcasting
- `WorkspaceLive.mount/3` — load artifacts from DB for all agent sessions
- `WorkspaceLive` cleanup paths (remove_agent, clear_team) — delete artifact rows

**Pros**:
- Immediate persistence on every artifact emit (not tied to hibernate cycle)
- Clean separation of concerns — artifacts have their own lifecycle
- Can query artifacts independently (e.g. "show me all papers found across sessions")
- Payload size doesn't bloat the checkpoint
- Survives agent process crashes even without a hibernate

**Cons**:
- More code: migration, schema, context, queries
- Extra DB writes on every tool call (one upsert per artifact emit)
- Need to handle the append mode correctly: load existing, concat, store
- Must manage cleanup in all delete/clear paths
- Slightly more complex mount logic

**Effort**: Medium — roughly half a day.

### Option C: Store in thread entries as a special entry kind

**Approach**: When a tool emits an artifact, also append a thread entry with `kind: :artifact` containing the artifact payload. On mount, scan thread entries for artifact-kind entries and reconstruct `@artifacts`.

**Changes required**:
- `ArtifactPlugin.handle_signal/2` — append a thread entry alongside the PubSub broadcast
- `WorkspaceLive.mount/3` — when loading messages, also extract artifact entries from the thread
- May need `UITurn.project_entries/1` changes to handle artifact entries

**Pros**:
- No new tables — uses existing thread_entries infrastructure
- Artifacts are ordered chronologically alongside messages
- Thread cleanup already covers artifact cleanup

**Cons**:
- Append mode is complex: need to scan all prior artifact entries for the same name and merge
- Thread entries table grows faster
- Querying "current artifact state" requires scanning/folding all entries
- Mixes concerns: thread entries are messages/events, not state
- Reconstruct-on-mount logic can be expensive for long threads

**Effort**: Medium, with ongoing complexity in the fold logic.

### Option D: Hybrid — Agent state + lazy DB fallback

**Approach**: Combine Option A (agent state) for the fast path with a lightweight DB write for durability. The ArtifactPlugin writes to agent state AND persists to a simple KV table. On mount, prefer in-memory agent state; fall back to DB if agent isn't running.

This mirrors the existing pattern for messages: prefer in-memory thread → fall back to Ecto storage.

**Effort**: Medium-large.

## Future consideration: Shared artifacts

The [agent data layer architecture](agent-data-layer-architecture.md) (Proposal C — Hybrid)
envisions three phases of artifact ownership:

| Phase | Ownership | Example |
|-------|-----------|---------|
| 1 (now) | Single agent produces artifacts | Arxiv agent → paper list |
| 2 (next) | Multiple agent types produce artifacts | SQL agent → query results, writer agent → markdown |
| 3 (future) | Multiple agents + user share and co-edit an artifact | Collaborative document |

Phase 3 fundamentally changes the data model: a shared artifact is **not owned by
a single agent session**. It lives at the workspace level, and any agent or the
human user can read/write it. The architecture doc proposes a `SharedDocument`
GenServer per artifact, with all parties (agents + LiveView) interacting through
it.

This has direct implications for the persistence choice:

- **Option A (agent state)** only works for Phase 1. A shared artifact has no
  single agent to checkpoint it. You'd need a second mechanism for Phase 3, 
  creating two persistence paths.

- **Option B (dedicated DB table keyed by session_id)** works for Phase 1-2 but
  the `session_id` foreign key is the wrong abstraction for Phase 3. Shared
  artifacts belong to a workspace, not a session.

- **Option C (thread entries)** is per-session by definition and doesn't extend
  to shared artifacts at all.

- **Option D (agent state + DB)** has the same Phase 3 problem as Option A.

## Recommendation

**Option A (agent state) now, with a migration path to a workspace-scoped DB
table when shared artifacts arrive.**

### Why Option A first

1. **Aligns with the architecture doc's design.** Proposal C explicitly uses
   Jido Memory Spaces (agent state) as the canonical store for single-agent
   artifacts. The ArtifactPlugin already declares `state_key: :artifacts`. The
   checkpoint/hibernate infrastructure already serializes and restores agent
   state. We just need to actually write artifact data into it.

2. **Minimal work.** The only changes are:
   - Make `ArtifactPlugin.handle_signal/2` merge artifact data into agent state
     (instead of returning Noop with no state change)
   - Load artifact state from agent on mount (alongside the existing message load)
   - No migration, no new schema, no new context module

3. **Artifacts already persist via hibernate.** After every LLM turn, `Runner`
   calls `hibernate_agent/1`, which checkpoints the full agent state (including
   the `:artifacts` key) to `jido_checkpoints`. On mount, `thaw` restores it.
   This is the exact same path messages use.

4. **No throwaway code.** When Phase 3 arrives and we introduce a dedicated
   artifacts table, the single-agent artifacts migrate naturally: read from
   checkpoint, write to new table, done. The LiveView rendering code is
   identical either way — it reads from `@artifacts`.

### What changes now

```
1. ArtifactPlugin.handle_signal/2
   - Accumulate artifact data into plugin state (returned to framework)
   - Continue broadcasting via PubSub (no change to real-time path)

2. WorkspaceLive.mount/3
   - After loading agent state, extract agent.state.artifacts
   - Populate @artifacts assign from it (instead of empty map)

3. WorkspaceLive cleanup paths
   - No change needed — checkpoint deletion already cleans up agent state
```

### Known limitations (acceptable for Phase 1-2)

- **Artifacts persist at the end of an LLM turn** (when `hibernate` is called),
  not on every emit. If the server crashes mid-turn, the latest artifact update
  is lost. This matches the existing behavior for messages — both use the same
  checkpoint cycle.

- **Checkpoint JSONB grows** with artifact payloads. Paper lists are typically
  tens of KB; this is fine. If artifacts grow to MB+ (large SQL result sets),
  we'd want the DB table migration sooner.

- **Plugin state mutation + routing override.** The current `handle_signal`
  returns `{:ok, {:override, Noop}}`. We need to verify that the Jido plugin
  API allows returning both a state update and a routing override. If not, a
  small adapter (separate signal handler or post-broadcast state write) is
  needed.

### Migration path to Phase 3

When shared artifacts become a requirement, introduce the DB table then — but
scoped to the **workspace**, not the session:

```elixir
# Future migration — NOT needed now
create table(:artifacts, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all), null: false
  add :owner_session_id, :string  # nullable — nil for shared artifacts
  add :name, :string, null: false
  add :data, :map, null: false, default: %{}
  add :shared, :boolean, null: false, default: false
  timestamps(type: :utc_datetime_usec)
end

create unique_index(:artifacts, [:workspace_id, :owner_session_id, :name])
create index(:artifacts, [:workspace_id])
```

Key differences from the original Option B schema:
- **`workspace_id` as primary scope**, not `session_id`
- **`owner_session_id` is nullable** — `nil` means the artifact is shared
  across all agents in the workspace
- **`shared` flag** distinguishes workspace-wide vs agent-private artifacts
- Unique constraint is `(workspace_id, owner_session_id, name)` — two agents
  can each have a `"papers"` artifact, and there can also be a shared one

At that point, the `ArtifactPlugin` writes to DB instead of (or in addition to)
agent state, and a `SharedArtifact` GenServer manages the real-time
collaboration layer on top.

## Out of scope (but worth noting)

- **Client-side caching**: Could store artifacts in sessionStorage/localStorage
  via a JS hook for instant display before the LiveView mount completes. Would
  be an enhancement on top of any server-side option.
- **Artifact versioning**: Tracking history of artifact changes (useful for
  undo/replay). The current modes (replace/append) don't need this yet.
- **Real-time shared editing**: The architecture doc proposes OT/CRDTs via a
  SharedDocument GenServer. This is a significant effort orthogonal to basic
  persistence and should be designed separately when Phase 3 begins.
