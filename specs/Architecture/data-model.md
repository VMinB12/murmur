# Data Model

## Purpose

This document defines Murmur's canonical domain model: the entities, identities, relationships, derived read models, and invariants that matter across packages and tickets.

Use this document to answer questions such as:

- what concepts are part of Murmur's stable domain model?
- which identities are canonical, and which are derived for rendering or persistence?
- which objects are domain entities versus read models or storage representations?

For the detailed conversation projection mechanics, see [conversation-read-model.md](conversation-read-model.md). For cross-boundary payloads and signal shapes, see [data-contracts.md](data-contracts.md).

## Modeling Layers

Murmur keeps three layers distinct:

- Domain model: conceptual entities and invariants such as workspaces, agent sessions, tasks, actor identity, and conversations.
- Derived or read models: shapes derived from domain facts for rendering or orchestration, such as the canonical conversation read model.
- Serialization and persistence representations: database rows, thread entries, and PubSub payload encodings that carry or store the canonical model but are not themselves the model.

## Canonical Domain Concepts

### Workspace

The workspace is Murmur's top-level collaboration container.

- Identity: `workspace.id`
- Owns: agent sessions, tasks, workspace-scoped PubSub topics, and the shared collaboration context
- Invariants:
  - a workspace is the isolation boundary for agent collaboration
  - agent display names are only required to be unique within one workspace
  - task and artifact visibility is scoped to the workspace even when the producing session is individual

### Agent Session

An agent session is Murmur's long-lived runtime identity for one agent inside one workspace.

- Identity: `session.id`
- Belongs to: one workspace
- Has: an `agent_profile_id`, a human-facing `display_name`, persisted state, a thread, artifact state, and runtime busy or idle status
- Relationships:
  - one workspace has many agent sessions
  - one session owns one persisted thread history
  - one session can emit many artifacts and assistant turns over time
- Invariants:
  - `(workspace_id, display_name)` is unique
  - `session.id` is the stable join key for runtime state, persistence, PubSub topics, artifacts, and canonical conversation state

### Actor Identity

`ActorIdentity` is the canonical semantic identity model for who caused or authored a message-like fact.

- Identity fields: `kind`, optional `name`, optional `id`
- Kinds: `:agent`, `:human`, `:programmatic`, `:system`, `:unknown`
- Purpose:
  - separates semantic authorship from presentation wording
  - lets Murmur distinguish the currently running agent from the originating actor of an ingress message
- Invariants:
  - actor semantics are explicit data, not inferred from text prefixes
  - host apps may choose labels like `You`, but those labels are not the source of truth

### Conversation

The conversation for a session is the ordered record of top-level visible user messages and assistant steps associated with that session.

- Canonical owner: `jido_murmur`
- Identity root: `session.id`
- Major sub-identities:
  - `request_id` identifies one outer run
  - assistant-step identity is Murmur-owned inside a request, such as `req-123-step-1`
  - visible ingress user-message identity is Murmur-owned at ingress time and persists across replay
- Invariants:
  - top-level ordering is by Murmur-owned first-seen metadata
  - user-visible programmatic messages and direct human messages remain top-level user messages
  - tool calls and tool results stay nested inside the assistant step that produced them

### Task

Tasks are shared work items inside a workspace.

- Identity: `task.id`
- Belongs to: one workspace
- Core fields: title, description, assignee, status
- Relationships:
  - tasks can be created by humans or agents
  - tasks can target either a human assignee or an agent display name
- Invariants:
  - task state is workspace-visible shared state, not private agent state
  - task assignment notifications are downstream effects of task changes, not the task itself

### Artifact

An artifact is durable output emitted by an agent session for later viewing or reuse.

- Identity: artifact name within a session-scoped artifact map
- Belongs to: one session, one workspace
- Typical examples: paper lists, SQL results, HTML views, charts
- Invariants:
  - the canonical durable state is the artifact value held in agent state and checkpoints
  - UI open or active panel state is presentation-only and not part of the artifact model

## Derived And Read Models

### ConversationReadModel

`ConversationReadModel` is Murmur's canonical derived conversation state.

- Owner: `JidoMurmur.ConversationProjector`
- Identity root: `session.id`
- Contents:
  - top-level canonical `DisplayMessage` values
  - projector-only state that tracks assistant-step progression by `request_id`
- Purpose:
  - unify live incremental updates and replayed history under one model
  - give the projector richer state than a bare list of rendered messages

This is a derived model, not a separate domain entity.

### DisplayMessage

`DisplayMessage` is the canonical top-level presentation value used by chat surfaces.

- Identity: `message.id`
- Roles: `user` or `assistant`
- Contains:
  - actor metadata
  - content
  - first-seen ordering metadata
  - assistant-step fields like `request_id`, `step_index`, `thinking`, `tool_calls`, `usage`, and `status`
- Invariants:
  - it is the rendering model for chat views
  - it is not the persistence format

### DisplayMessage.ToolCall

`DisplayMessage.ToolCall` is a nested value type inside an assistant step.

- Identity: tool-call id when available
- Meaning: the current or completed lifecycle state of one tool invocation within a specific assistant step
- Invariant:
  - tool results do not become separate top-level conversation items

## Persistence And Representation Models

These shapes are important, but they are not the canonical domain model.

### Workspace Row

Persisted representation of the workspace entity in Ecto and PostgreSQL.

### Agent Session Row

Persisted representation of the agent-session entity in Ecto and PostgreSQL.

### Thread Entry

Persisted representation of conversation facts in the Jido thread store.

- Carries: `kind`, `payload`, `refs`, `seq`, `at`
- Used by: `ConversationReadModel.EntryProjector`
- Important distinction:
  - thread entries are storage facts
  - they are replayed into the canonical conversation read model rather than rendered directly

### Checkpoint

Persisted representation of whole-agent runtime state for thaw and restore.

- Carries: serialized agent state, including artifact state and thread state
- Important distinction:
  - checkpoints are recovery snapshots, not public runtime contracts

## Core Relationships

- one workspace has many agent sessions
- one workspace has many tasks
- one agent session owns one conversation thread and one canonical conversation read model
- one agent session may emit many artifacts
- one outer request may yield many assistant steps
- one assistant step may contain many tool calls
- one visible ingress message has one Murmur-owned message identity even if it is later replayed from persisted entries

## Architectural Invariants

### Explicit Actor Semantics

Actor meaning is always carried as data. Murmur does not rely on sender-name prefixes embedded in content to recover semantics.

### Canonical Ordering

Visible top-level conversation ordering is governed by Murmur-owned first-seen metadata, not by arrival order in the browser and not by raw thread-entry sequence alone.

### Stable Visible Ingress Identity

Direct human-visible ingress and visible programmatic ingress receive stable Murmur-owned message identity and first-seen ordering metadata at ingress time, and replay preserves that identity.

### One Canonical Conversation Model

Live streaming updates, reconnect snapshots, and replayed history all pass through the same canonical conversation read model.

### Presentation State Is Not Canonical State

Transient UI concerns such as pending-send placeholders, open artifact panels, current view mode, or loading affordances are not part of the canonical domain model.

## When To Extend This Document

Update this document when Murmur changes:

- a canonical entity identity rule
- a cross-entity relationship that affects behavior or ownership
- a lifecycle invariant that more than one ticket or package depends on
- the boundary between domain entities and derived read models