# Research: CloudEvents Signal Alignment

**Feature Branch**: `005-cloudevents-alignment`  
**Date**: 2026-03-29

## Research Tasks

### R1: Current PubSub Message Format Inventory

**Context**: Need a complete list of all PubSub message formats to plan the signal migration.

**Finding**: Five distinct raw tuple patterns identified:

| Pattern | Source | Topic |
|---------|--------|-------|
| `{:artifact_update, session_id, name, data, mode}` | ArtifactPlugin | `agent_artifacts:#{session_id}` |
| `{:agent_signal, session_id, signal}` | StreamingPlugin | `agent_stream:#{session_id}` |
| `{:message_completed, session_id, response}` | Runner | `workspace:#{wid}:agent:#{sid}` |
| `{:new_message, session_id, msg}` | TellAction | `workspace:#{wid}:agent:#{sid}` |
| `{:task_created, task}` / `{:task_updated, task}` | AddTask/UpdateTask | `jido_tasks:tasks:#{wid}` |

Note: `{:agent_signal, session_id, signal}` already wraps a `Jido.Signal` struct, but the outer tuple is still ad-hoc.

**Decision**: Migrate all five patterns to signal envelopes. Each broadcast becomes a `%Jido.Signal{}` with proper `type`, `source`, `subject`, `id`, and `time` fields. The bare tuple wrapper is eliminated.

**Rationale**: Uniform envelope enables single handler pattern in LiveViews, audit logging, and future event replay.

### R2: Subject Field URI Conventions

**Context**: Need to define consistent subject URIs for all signal types.

**Finding**: CloudEvents spec says `subject` should identify the entity the event is about, using a relative URI when the entity is scoped within the `source`.

**Decision**: Subject URI patterns:
- Artifact signals: `/agents/#{agent_id}` (artifact belongs to an agent)
- Task signals: `/workspaces/#{workspace_id}/tasks/#{task_id}`  
- Message signals: `/workspaces/#{workspace_id}/agents/#{session_id}`
- Streaming signals: `/agents/#{session_id}` (stream belongs to an agent session)

**Rationale**: Hierarchical URIs capture the containment relationship (workspaces contain agents, agents contain artifacts).

**Alternatives Considered**:
- Flat IDs (e.g., `agent_abc`) → rejected because they lose hierarchical context
- URNs (e.g., `urn:jido:agent:abc`) → rejected because URI paths are simpler and more CloudEvents-idiomatic

### R3: Signal.ID vs General-Purpose UUID

**Context**: Code uses `Signal.ID.generate!()` for non-signal purposes (message IDs, task tracking IDs).

**Finding**: Three call sites use `Signal.ID.generate!()` (which generates UUID7 via Uniq.UUID.uuid7()):
- `TellAction` — inter-agent message IDs
- `AddTask` — task creation
- `UpdateTask` — task updates

These are entity IDs, not signal IDs. Using `Signal.ID` adds a false semantic dependency on jido_signal.

**Decision**: Replace with `Uniq.UUID.uuid7()` at non-signal call sites. `Uniq` is already a transitive dependency (via jido_signal), so it's available without adding new deps. If we want to avoid depending on the transitive path, `Ecto.UUID.generate()` (UUID v4) is also available.

**Rationale**: Clarifies intent — signal IDs are for signals, UUID generation for entities.

**Alternatives Considered**:
- Creating a `JidoMurmur.ID` wrapper → rejected because it's unnecessary indirection for a one-liner

### R4: Typed Signal Module Patterns in Jido

**Context**: Need to understand how `use Jido.Signal` works for typed signal definitions.

**Finding**: The `jido_signal` library supports:
```elixir
defmodule MySignal do
  use Jido.Signal,
    type: "my.custom.signal",
    default_source: "/my/service",
    schema: [user_id: [type: :string, required: true], ...]
end
```

This gives: compile-time schema validation via NimbleOptions, default `type` and `source` values, and a `new/1` constructor that validates data.

**Decision**: Define typed signal modules for all core signal types:
- `JidoArtifacts.Signals.ArtifactEmitted` — type: `artifact.{name}`
- `JidoMurmur.Signals.MessageCompleted` — type: `murmur.message.completed`
- `JidoMurmur.Signals.MessageReceived` — type: `murmur.message.received` (replaces `:new_message`)
- `JidoTasks.Signals.TaskCreated` — type: `task.created`
- `JidoTasks.Signals.TaskUpdated` — type: `task.updated`

Streaming signals (`ai.llm.delta`, etc.) are already typed by the Jido AI framework and don't need custom modules.

**Rationale**: Typed modules serve as living documentation, provide compile-time validation, and make the event catalog discoverable from code.

### R5: LiveView Handler Migration Strategy

**Context**: All LiveView handlers in `WorkspaceLive` use tuple pattern matching. Need to migrate atomically.

**Finding**: Handler locations in `WorkspaceLive`:
- `handle_info({:agent_signal, ...})` — already wraps a Signal, easiest migration
- `handle_info({:artifact_update, ...})` — 5-element tuple
- `handle_info({:message_completed, ...})` — 3-element tuple
- `handle_info({:new_message, ...})` — 3-element tuple
- `handle_info({:task_created, ...})` / `handle_info({:task_updated, ...})` — 2-element tuples

**Decision**: Migrate all handlers at once in a single commit. Each handler pattern-matches on `%Jido.Signal{type: "...", data: data}` instead of tuples. The streaming handler drops the outer `{:agent_signal, ...}` wrapper.

**Rationale**: Atomic migration prevents silent message drops that would occur if publishers switch to signals but subscribers still expect tuples.

### R6: Signal Catalog Document Structure

**Context**: Need to document all signal types for developer reference.

**Decision**: Create `docs/signal-catalog.md` with columns: Type, Source, Subject Pattern, Data Schema, Emitter Module, Handler(s), PubSub Topic. Updated whenever new signal types are added.

**Rationale**: Living documentation that serves as the single reference for signal contracts.
