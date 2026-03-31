# Data Model: Multi-Agent Chat Interface

**Feature**: `001-multi-agent-chat`  
**Date**: 2026-03-25

## Entity Relationship Diagram

```
Workspace 1──* AgentSession 1──* Message
```

## Entities

### Workspace

The top-level container for a multi-agent session.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| id | uuid | PK, generated | |
| name | string | required, max 255 | User-provided workspace name |
| inserted_at | utc_datetime_usec | auto | |
| updated_at | utc_datetime_usec | auto | |

**Relationships**: has_many `AgentSession`

### AgentSession

An active instance of an Agent Profile within a Workspace. Each session has its own independent conversation history.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| id | uuid | PK, generated | Also used as Jido agent ID and PubSub topic component |
| workspace_id | uuid | FK → Workspace, required | indexed |
| agent_profile_id | string | required | References hardcoded catalog entry (e.g., "sql_agent") |
| display_name | string | required, max 255 | User-given name when adding agent to workspace |
| status | string | default "idle" | "idle" or "busy"; mirrors GenServer state |
| inserted_at | utc_datetime_usec | auto | |
| updated_at | utc_datetime_usec | auto | |

**Relationships**: belongs_to `Workspace`, has_many `Message`

**Indexes**: `[:workspace_id]`, unique: `[:workspace_id, :display_name]`

**Notes**: Multiple instances of the same profile are allowed per spec, but display names MUST be unique within a workspace (enforced by unique DB index). The `status` column is informational (the GenServer is the source of truth at runtime).

### Message

A single entry in an Agent Session's conversation history.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| id | uuid | PK, generated | |
| agent_session_id | uuid | FK → AgentSession, required | indexed |
| role | string | required | One of: "user", "assistant", "tool_call", "tool_result" |
| content | text (string) | nullable | Message body; null for tool_call messages |
| sender_name | string | nullable | Set when message is from another agent (e.g., "[SQL Agent]") or from user |
| tool_calls | map | nullable, default nil | JSON array of tool call objects for role="tool_call" |
| tool_call_id | string | nullable | References a specific tool call for role="tool_result" |
| metadata | map | default %{} | Extensible metadata (e.g., hop_count for inter-agent messages) |
| inserted_at | utc_datetime_usec | auto | |

**Relationships**: belongs_to `AgentSession`

**Indexes**: `[:agent_session_id]`, `[:agent_session_id, :inserted_at]`

**Notes**: Messages are append-only. The `inserted_at` + `agent_session_id` index supports efficient ordered retrieval of a session's history. No `updated_at` — messages are immutable once persisted.

## Agent Profile (In-Memory Only)

Agent Profiles are **not** database entities. Each profile is a `Jido.AI.Agent` module (e.g., `Murmur.Agents.Profiles.SqlAgent`) that declares its own `model`, `system_prompt`, and `tools`. The `Murmur.Agents.Catalog` module maps profile IDs to their module plus display-only metadata.

| Field | Type | Notes |
|-------|------|-------|
| id | string | Unique identifier (e.g., "sql_agent") |
| agent_module | module | The `Jido.AI.Agent` module (e.g., `Murmur.Agents.Profiles.SqlAgent`) |
| description | string | Short description shown in catalog UI |
| color | string | Tailwind color class for the agent's header |

## State Transitions

### AgentSession Status

```
          user message / tell message
idle ──────────────────────────────────► busy
  ▲                                        │
  │         execution completes            │
  └────────────────────────────────────────┘
```

- **idle → busy**: When a message arrives (from user or another agent) and the agent begins LLM execution
- **busy → idle**: When the execution Task completes and the GenServer processes `{:completed, final_history}`
- While **busy**: incoming messages are appended to `pending_injections` and drained before the next LLM call

## Validation Rules

- **Workspace.name**: Required, max 255 characters
- **AgentSession.display_name**: Required, max 255 characters, unique within workspace (DB constraint)
- **AgentSession.agent_profile_id**: Must reference a valid entry in `Murmur.Agents.Catalog`
- **Message.role**: Must be one of `["user", "assistant", "tool_call", "tool_result"]`
- **Message.content**: Required when role is "user" or "assistant"
- **Maximum agents per workspace**: 8 (enforced at application level, not DB constraint)
- **Inter-agent hop depth**: Maximum 5 (enforced via metadata.hop_count in TellAction)
