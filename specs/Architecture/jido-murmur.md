# jido_murmur — Core Backend

## Purpose

Core orchestration backend for the multi-agent chat platform. Provides workspace management, agent lifecycle control, inter-agent communication, stateful session storage, observability integration, and a plugin architecture for extending agent behavior.

## Public API

### AgentHelper — Agent Lifecycle

| Function | Signature | Purpose |
|----------|-----------|---------|
| `start_agent/1` | `(session) → {:ok, pid}` | Start or restore an agent from checkpoint |
| `load_messages/1` | `(session) → [map()]` | Load conversation history (live process or storage) |
| `load_artifacts/1` | `(session) → [map()]` | Load generated artifacts from agent state |
| `subscribe/1` | `(session) → :ok` | Subscribe to all PubSub topics for a session |

### Workspaces — Workspace & Session Management

| Function | Purpose |
|----------|---------|
| `create_workspace/1` | Create a new workspace |
| `get_workspace!/2` | Fetch a workspace with authorization |
| `list_workspaces/0` | List all workspaces |
| `create_agent_session/2` | Create an agent session in a workspace |
| `get_agent_session!/1` | Fetch a session |
| `list_agent_sessions/1` | List sessions in a workspace |
| `find_agent_session_by_name/2` | Lookup session by display name |
| `delete_agent_session/1` | Delete a session |

### Ingress — Delivery Coordination

| Function | Purpose |
|----------|---------|
| `deliver/3` | Route direct human-visible input through the session coordinator |
| `deliver_programmatic/3` | Route visible programmatic input through the shared canonical ingress path |
| `deliver_input/2` | Deliver canonical ingress input directly |
| `ensure_started/1` | Start or reuse the per-session coordinator |

### Runner — Single Run Execution

| Function | Purpose |
|----------|---------|
| `start_run/2` | Start one ask/await cycle for normalized ingress input |
| `active?/1` | Check if agent has an active run task |

### Catalog — Agent Profile Registry

| Function | Purpose |
|----------|---------|
| `list_profiles/0` | List registered agent profiles from config |
| `get_profile!/1` | Get profile metadata including agent module |
| `agent_module/1` | Resolve profile name to agent module |
| `agent_color/2` | Get Tailwind CSS color classes for agent |

### Topics — PubSub Hierarchy

All topics follow `workspace:{wid}:...` for multi-workspace isolation:

| Function | Topic Pattern |
|----------|---------------|
| `agent_messages/2` | `workspace:{wid}:agent:{sid}:messages` |
| `agent_stream/2` | `workspace:{wid}:agent:{sid}:stream` |
| `agent_artifacts/2` | `workspace:{wid}:agent:{sid}:artifacts` |
| `workspace_tasks/1` | `workspace:{wid}:tasks` |
| `workspace/1` | `workspace:{wid}` |

## Internal Architecture

### Agent Lifecycle (AgentHelper + Ingress + Runner)

1. `start_agent/1` restores state from a checkpoint (if available) or creates a fresh agent via Jido
2. Conversation history (thread) is persisted in PostgreSQL using the `Jido.Storage` adapter
3. `Ingress.Input.refs` is the canonical source of Murmur routing and observability metadata
4. `Ingress.Metadata` projects that canonical metadata once into tool-visible runtime context in `Runner.start_run/2`
5. `Ingress` serializes delivery decisions per session
6. Idle agents start a fresh `ask/await` run through `Runner.start_run/2`
7. Busy agents receive native `steer` or `inject` follow-up input against the active ReAct request
8. Completed responses trigger `MessageCompleted` signals broadcast via PubSub

### Inter-Agent Communication (TellAction + MessageInjector)

- Agents use the `tell` action for fire-and-forget inter-agent messages
- Messages route by display name through `Ingress.deliver_programmatic/3`
- Inter-agent hop depth is configurable via `config :jido_murmur, tell_hop_limit: <non_negative_integer>` and defaults to `5`
- Hop-limit exhaustion returns an informative tool result (`delivered: false`, `blocked: :hop_limit_reached`) instead of failing the agent run
- Hop count propagates through canonical ingress metadata, so downstream runs see the current depth in both tool context and `extra_refs`
- `MessageInjector` (a ReAct RequestTransformer) adds Murmur team context to the system prompt and does not own follow-up delivery

### Canonical Ingress Metadata Boundary

- `JidoMurmur.Ingress.Input` owns canonical ingress input construction and validation
- `JidoMurmur.Ingress.Metadata` is the typed projection of Murmur-owned ingress metadata carried inside `refs`
- Known metadata fields are `interaction_id`, `workspace_id`, `sender_name`, `origin_actor`, `sender_trace_id`, and `hop_count`
- Metadata keys are atom-keyed in the cleaned runtime path; fallback string-key readers are not retained in this unpublished package surface
- `Runner` projects tool-visible runtime context from canonical metadata once, instead of performing ad hoc ref lookups in downstream code
- Runtime context distinguishes `current_actor` from `origin_actor`; compatibility aliases such as `sender_name` remain transitional outputs, not the long-lived semantic contract

### Shared Programmatic Delivery

- `JidoMurmur.Ingress.ProgrammaticDelivery` is the single visible programmatic delivery path for tells and task-assignment notifications
- The helper builds canonical ingress input first, delivers it through `Ingress.deliver_input/2`, then emits `MessageReceived` using the same canonical metadata
- Visible programmatic payloads now align on one shape: `content`, `kind`, `interaction_id`, `sender_name`, `origin_actor`, `sender_trace_id`, and `hop_count`
- Task-assignment notifications and tell messages no longer duplicate message-signal assembly, canonical input assembly, or ad hoc metadata shaping in their callers

### Canonical Display Projection

- `JidoMurmur.DisplayMessage` is the canonical UI-facing message model for chat surfaces
- `UITurn.project_entries/1` is the shared projection boundary that converts persisted thread entries into display messages with explicit actor semantics
- The projection boundary normalizes persisted string-keyed payloads once, but it no longer infers actor identity from content prefixes such as `"[Alice]: ..."`
- Display labels are derived from actor metadata and rendering helpers, not treated as the runtime source of truth

### Request Transformation Pipeline

Multiple transformers are chained via `ComposableRequestTransformer`:
- Each can override `:messages`, `:llm_opts`, and `:tools`
- Overrides are deep-merged (messages replaced wholesale, llm_opts merged by key)

### Storage Duality

- Active agents maintain thread state in memory (Jido process)
- `load_messages/artifacts` checks the live process first, falls back to PostgreSQL
- Checkpoints stored in `jido_murmur_checkpoints` for recovery
- Thread entries stored individually in `jido_murmur_thread_entries` with sequence ordering

### Plugin Architecture

All plugins use `Jido.Plugin`, declaration-ordered:

| Plugin | Purpose |
|--------|---------|
| `StreamingPlugin` | Broadcasts lifecycle signals via PubSub for real-time UI |

### Observability

- See [observability.md](observability.md) for the current observability model.
- `Runner` owns root turn boundaries and exports discussion-scoped `session.id` values.
- `ConversationCache` keeps direct chat grouped into one active discussion until inactivity timeout rollover.
- `ReqLLMTracer` feeds detailed LLM telemetry into Murmur-owned span state.

### ETS Tables (owned by TableOwner GenServer)

| Table | Purpose |
|-------|---------|
| `:jido_murmur_active_runners` | Track active run tasks per session |
| `:jido_murmur_obs_conversations` | Active direct-chat discussion id per agent session |

## Data Models

### Workspace

```
jido_murmur_workspaces
├── id: binary_id (PK)
├── name: string (required, max 255)
├── owner_id: string (optional, indexed)
├── metadata: map
└── timestamps (utc_datetime_usec)
```

### AgentSession

```
jido_murmur_agent_sessions
├── id: binary_id (PK)
├── workspace_id: binary_id (FK → workspaces, cascade delete)
├── agent_profile_id: string (maps to Catalog profile)
├── display_name: string (required, max 255)
├── status: :idle | :busy (default :idle)
├── owner_id: string (optional)
├── metadata: map
├── unique index: (workspace_id, display_name)
└── timestamps (utc_datetime_usec)
```

### Checkpoint (Jido.Storage adapter)

```
jido_murmur_checkpoints
├── key: string (PK, format: "agent_module:session_id")
├── data: map (serialized agent snapshot)
└── timestamps (utc_datetime_usec)
```

### ThreadEntry (Jido.Storage adapter)

```
jido_murmur_thread_entries
├── id: binary_id (PK)
├── thread_id: string (= session.id)
├── seq: integer (sequence ordering)
├── kind: string (:message, :ai_message, :tool_call, etc.)
├── payload: map
├── refs: map
├── at: bigint (system time in nanoseconds)
├── unique index: (thread_id, seq)
└── inserted_at (utc_datetime_usec)
```

### ActorIdentity (shared semantic model)

```elixir
%ActorIdentity{
  kind: :agent | :human | :programmatic | :system | :unknown,
  name: String.t() | nil,
  id: String.t() | nil
}
```

### DisplayMessage (presentation struct)

```elixir
%DisplayMessage{
  id: String.t(),
  role: String.t(),
  content: String.t(),
  actor: ActorIdentity.t() | nil,
  sender_name: String.t() | nil,
  thinking: String.t() | nil,
  tool_calls: [%ToolCall{}],
  usage: map() | nil,
  status: atom() | nil
}
```

### UITurn (projection helper)

```elixir
%UITurn{
  id: String.t(),
  thinking: String.t() | nil,
  tool_calls: [%ToolCall{id, name, args, result, status}],
  content: String.t(),
  sender_name: String.t() | nil,
  status: :thinking | :tool_calling | :completed | :error
}
```

## Signal Types

| Signal | Type | Emitted By |
|--------|------|------------|
| `MessageReceived` | `murmur.message.received` | `Ingress.ProgrammaticDelivery` |
| `MessageCompleted` | `murmur.message.completed` | `Runner` |

## Dependencies

**Requires:** `jido ~> 2.2`, `jido_ai ~> 2.1`, `jido_action ~> 2.2`, `jido_signal ~> 2.1`, `phoenix_pubsub ~> 2.0`, `ecto_sql ~> 3.13`, `postgrex`, `jason ~> 1.2`, `agent_obs ~> 0.1.4`

**Used by:** `jido_murmur_web`, `jido_tasks`, `jido_sql`, `murmur_demo`

## Configuration

```elixir
# Required
config :jido_murmur,
  repo: MyApp.Repo,
  pubsub: MyApp.PubSub,
  jido_mod: MyApp.Jido,
  otp_app: :my_app

# Optional
config :jido_murmur,
  profiles: [MyApp.Agents.ProfileA, MyApp.Agents.ProfileB],
  authorize: MyApp.Authorization,
  artifact_renderers: %{"type" => RendererModule},
  tell_hop_limit: 5
```
