# Research: Platform Infrastructure Improvements

**Feature Branch**: `006-platform-improvements`  
**Date**: 2026-03-29

## Research Tasks

### R1: Current PubSub Topic Inventory & Inconsistencies

**Context**: Need to catalog all topic formats and identify inconsistencies.

**Finding**: Current topic patterns:
- `"agent_artifacts:#{session_id}"` — artifact plugin (underscore-separated, no workspace)
- `"agent_stream:#{session_id}"` — streaming plugin (underscore-separated, no workspace)
- `"workspace:#{wid}:agent:#{sid}"` — runner/tell (colon-separated, includes workspace)
- `"jido_tasks:tasks:#{wid}"` — tasks (package-prefixed, workspace at end)
- `"workspace:#{wid}"` — workspace-level subscription (mentioned in AgentHelper)

**Decision**: Standardize all topics to hierarchical colon-separated format with workspace context:
- `"workspace:#{wid}:agent:#{sid}:artifacts"` (was `agent_artifacts:#{sid}`)
- `"workspace:#{wid}:agent:#{sid}:stream"` (was `agent_stream:#{sid}`)
- `"workspace:#{wid}:agent:#{sid}:messages"` (was `workspace:#{wid}:agent:#{sid}`)
- `"workspace:#{wid}:tasks"` (was `jido_tasks:tasks:#{wid}`)

Centralize in `JidoMurmur.Topics` helper module.

**Rationale**: Consistent hierarchical format makes topics predictable, enables wildcard subscriptions in the future, and includes workspace context for multi-workspace support.

**Alternatives Considered**:
- Keeping package-prefixed topics (e.g., `jido_tasks:...`) → rejected because it fragments the namespace and doesn't include workspace context
- Dot-separated topics → rejected because colons are the established Phoenix PubSub convention

### R2: Workspace ID Threading Through Plugins

**Context**: Artifact and streaming plugins currently don't have access to workspace_id.

**Finding**: Plugin `handle_signal/2` receives context with `context.agent` (the agent struct). Agent state contains session info set during initialization. Checking current agent initialization:
- `JidoMurmur.Workspaces.create_agent_session/2` creates sessions with `workspace_id`
- Agent is started with `session.id` as its ID
- Workspace ID is stored in the session record, accessible via `JidoMurmur.Workspaces.get_agent_session!/1`

The workspace_id is NOT currently in the agent's state map. It's only in the Ecto session record.

**Decision**: Thread workspace_id into agent state during agent initialization. When `Runner.start_agent_for_session/1` starts an agent, set `workspace_id` in the agent's state via the initial state map. Plugins then access it via `context.agent.state.workspace_id`.

**Rationale**: Adding to agent state is the simplest path. Plugins already access `context.agent.state` for artifacts. This avoids extra DB queries in plugin callbacks.

**Alternatives Considered**:
- Look up session from agent ID in plugin → rejected because it adds a DB query to every signal handling
- Pass workspace_id through signal metadata → rejected because it would need to be added to every signal emission point

### R3: Startup Configuration Validation

**Context**: Missing config causes cryptic errors deep in the stack. Need clear startup validation.

**Finding**: Current startup flow has no explicit validation. `JidoMurmur.repo()` calls `Application.fetch_env!(:jido_murmur, :repo)` which raises a generic `ArgumentError` if missing. Same for `pubsub/0`, `jido_mod/0`.

**Decision**: Add `JidoMurmur.Config` module with `validate!/0` function called early in `JidoMurmur.Supervisor.init/1`. Validates required keys: `:repo`, `:pubsub`, `:jido_mod`, `:otp_app`. On failure, raises with a message that names the missing key and suggests running the install task.

Similarly for `JidoTasks.Config.validate!/0` checking `:repo` and `:pubsub`.

**Rationale**: Fail fast with actionable errors. Validation in supervisor init runs before any child process needs the config.

**Alternatives Considered**:
- Compile-time validation via Application.compile_env → rejected because config is typically set at runtime (runtime.exs)
- Warning instead of error → rejected because missing config will crash anyway; better to crash immediately with a clear message

### R4: Telemetry Conventions for jido_tasks

**Context**: jido_tasks has no telemetry. jido_murmur uses `:telemetry.execute/3` in plugins.

**Finding**: jido_murmur telemetry patterns:
- `[:jido_murmur, :artifact, :store]` — in ArtifactPlugin
- `[:jido_murmur, :streaming, :broadcast]` — in StreamingPlugin

Standard Phoenix/Ecto convention: `[:app_name, :resource, :action]`.

**Decision**: Add telemetry to jido_tasks context functions:
- `[:jido_tasks, :task, :create]` — with `%{task_id: id}` metadata
- `[:jido_tasks, :task, :update]` — with `%{task_id: id, old_status: s, new_status: s}` metadata
- `[:jido_tasks, :task, :list]` — with `%{workspace_id: wid, count: n}` metadata

Emit from `Tasks` context module (not from tool actions) so telemetry fires regardless of the caller.

**Rationale**: Context-level telemetry captures all operations, not just those triggered by agent tools. Follows established `:telemetry` conventions.

### R5: Agent Profile Behaviour Design

**Context**: Current profiles use convention (module attributes via `use Jido.AI.Agent`). No compile-time enforcement.

**Finding**: Agent profiles currently define:
- `name` — via `use Jido.AI.Agent, name: "..."` (macro option, not a callback)
- `description` — via macro option
- `system_prompt` — via macro option
- `tools` — via macro option
- `plugins` — via macro option
- `catalog_meta/0` — custom function defined by convention

The `Jido.AI.Agent` macro generates a module with these options baked in at compile time. There's no behaviour to enforce the presence of options.

**Decision**: Define `JidoMurmur.AgentProfile` behaviour with callbacks:
```elixir
@callback name() :: String.t()
@callback description() :: String.t()
@callback system_prompt() :: String.t()
@callback tools() :: [module()]
@callback plugins() :: [module()]
@callback opts() :: keyword()
```

Profile modules add `@behaviour JidoMurmur.AgentProfile` alongside `use Jido.AI.Agent`. The `Jido.AI.Agent` macro already generates functions for these, so adding the behaviour just adds compile-time checking.

**Rationale**: Low-cost addition that catches missing callback implementations at compile time. No runtime overhead.

**Alternatives Considered**:
- Validating profiles at startup via the Catalog module → rejected because it catches errors at runtime, not compile time
- Protocol instead of behaviour → rejected because profiles are modules with callbacks, not data types to dispatch on

### R6: Migration Strategy for PubSub Topics

**Context**: Changing topic strings will break existing subscribers if not coordinated.

**Finding**: All PubSub subscribers are in:
- `AgentHelper.subscribe/1` — subscribes to 3 topics
- `WorkspaceLive.mount/3` — subscribes to workspace + task topics

All publishers are in the modules identified in R1.

**Decision**: Coordinated migration in a single commit/PR:
1. Create `JidoMurmur.Topics` module with all topic functions
2. Update all subscribers to use new topic functions
3. Update all publishers to use new topic functions
4. Delete old inline topic strings

Since the app isn't deployed externally, no backwards compatibility period is needed.

**Rationale**: All code is in one repo (umbrella). Single commit ensures no subscriber/publisher mismatch.
