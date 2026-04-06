# Data Contracts

## Purpose

This document defines Murmur's important cross-boundary contracts: the stable shapes that producers and consumers rely on across packages, runtime boundaries, persistence boundaries, or UI surfaces.

Use this document to answer questions such as:

- what is the canonical shape at a boundary?
- who owns it?
- who produces it and who consumes it?
- how is it transported or persisted when the storage or wire format differs from the canonical shape?

For the conceptual entities and invariants behind these contracts, see [data-model.md](data-model.md).

## Reading Guide

Each contract describes:

- owner: which package or module owns the contract semantics
- producers: who emits or constructs it
- consumers: who relies on it
- canonical shape: the stable in-memory or conceptual contract
- transport or persistence representation: how it is carried across a runtime or storage boundary
- compatibility notes: what must remain aligned over time

## Contract Catalog

| Contract | Owner | Primary Producers | Primary Consumers |
|----------|-------|-------------------|-------------------|
| Canonical ingress input | `JidoMurmur.Ingress.Input` | `WorkspaceLive`, task notifications, tell delivery, other host-app producers | `Ingress`, `Coordinator`, `Runner` |
| Visible ingress message | `JidoMurmur.Signals.MessageReceived` | `JidoMurmur.Ingress.VisibleMessage` | LiveViews and other UI subscribers |
| Canonical conversation update | `JidoMurmur.Signals.ConversationUpdated` plus `DisplayMessage` | `ConversationProjector` | LiveViews and reconnect snapshot loaders |
| Run completion and failure | `MessageCompleted` and `murmur.request.failed` | `Runner` | UI orchestration, busy or idle tracking |
| Artifact update | `JidoArtifacts.SignalUpdate` and `Envelope` | artifact-producing agents and plugins | artifact panels and host-app renderers |
| Task updates | `TaskCreated`, `TaskUpdated`, and task records | humans, agent actions, `jido_tasks` | task board UI, assignee notification flow |
| Persisted thread entry replay | Jido thread entry format projected by Murmur | Jido runtime and strategy pipeline | `ConversationReadModel.EntryProjector` |

## Canonical Ingress Input

### Owner

`JidoMurmur.Ingress.Input`

### Producers

- direct human sends from host apps such as `murmur_demo`
- visible programmatic delivery from tell-like flows and task notifications
- any future host app that wants to hand canonical ingress to Murmur

### Consumers

- `JidoMurmur.Ingress`
- `JidoMurmur.Ingress.Coordinator`
- `JidoMurmur.Runner`

### Canonical Shape

The canonical ingress input contains:

- `content`
- `source`
- `refs`
- optional `expected_request_id`

`refs` is the canonical Murmur metadata boundary. Its typed projection is `JidoMurmur.Ingress.Metadata`.

Known metadata includes:

- `workspace_id`
- `sender_name`
- `origin_actor`
- `sender_trace_id`
- `hop_count`

Additional Murmur-owned fields may also travel in `refs` when they are part of a stable boundary, such as visible message identity or presentation reconciliation references.

### Transport Or Persistence Representation

- runtime control path: passed as Murmur input and then forwarded into Jido control payloads
- Jido request path: carried through `extra_refs`
- persistence path: written into user thread-entry `refs`
- runtime projection: normalized into `JidoMurmur.Ingress.Metadata`

### Compatibility Notes

- Murmur treats this as the canonical ingress contract; callers should not bypass it with ad hoc `ask`, `steer`, or `inject` payload shaping
- `refs` semantics are canonical even though thread-entry persistence stores them as generic maps

## Visible Ingress Message

### Owner

`JidoMurmur.Signals.MessageReceived`

### Producers

- `JidoMurmur.Ingress.VisibleMessage`

### Consumers

- `murmur_demo` LiveViews
- any host UI that wants to render visible top-level ingress messages while connected

### Canonical Shape

The visible ingress payload is a message-like shape with:

- Murmur-owned `id`
- `role`
- `content`
- `kind`
- first-seen ordering metadata
- actor metadata such as `sender_name`, `origin_actor`, `sender_trace_id`, and `hop_count`

This contract is for visible top-level user messages, including both direct human sends and visible programmatic sends.

### Transport Or Persistence Representation

- transport: `murmur.message.received` PubSub signal payload
- persistence linkage: the same visible identity and first-seen metadata are also carried in ingress refs and later replayed from persisted user thread entries

### Compatibility Notes

- the signal is the connected-client update contract
- persisted replay must preserve the same visible identity and ordering metadata rather than synthesizing a new user-message identity on reconnect

## Canonical Conversation Update

### Owner

`JidoMurmur.ConversationProjector` and `JidoMurmur.DisplayMessage`

### Producers

- `ConversationProjector.apply_signal/4`
- `ConversationProjector.reconcile_session/1`

### Consumers

- LiveView chat surfaces
- reconnect snapshot loaders
- any host app rendering Murmur's canonical top-level conversation model

### Canonical Shape

The top-level message contract is `DisplayMessage`.

Important semantics:

- assistant messages are assistant steps, not whole outer requests
- tool calls and tool results remain nested under the assistant step
- first-seen metadata defines top-level ordering

### Transport Or Persistence Representation

- connected transport: `murmur.conversation.updated` signals carrying one canonical `DisplayMessage`
- reconnect snapshot: `ConversationProjector.snapshot/1` returns the message list derived from the cached `ConversationReadModel`
- persistence representation: Jido thread entries replayed through `ConversationReadModel.EntryProjector`

### Compatibility Notes

- host UIs should render `DisplayMessage`, not raw `ai.*` signals and not raw thread-entry payloads
- the projector caches the full `ConversationReadModel`, not just rendered messages, so replay and live incremental updates share one canonical state model

## Run Completion And Failure

### Owner

`JidoMurmur.Runner`

### Producers

- `Runner` after await success or failure

### Consumers

- UI orchestration for busy or idle state
- reconnect or completion handling in host apps

### Canonical Shape

- completion: `session_id`, `request_id`, `response`
- failure: `session_id`, `reason`

These are orchestration contracts, not the rich rendering contract for canonical conversation state.

### Transport Or Persistence Representation

- transport only: PubSub signals
- persisted assistant content still reconciles through thread entries and the conversation projector

### Compatibility Notes

- a completion signal does not replace the conversation projection boundary
- UI consumers should treat it as lifecycle state, not as the full assistant-message payload

## Artifact Update

### Owner

`JidoArtifacts.SignalUpdate` and `JidoArtifacts.Envelope`

### Producers

- artifact-producing agents and plugins

### Consumers

- artifact badge renderers
- artifact panels and specialized renderers

### Canonical Shape

- envelope: stable artifact value plus versioning and provenance metadata
- signal update: artifact name plus current envelope or deletion

### Transport Or Persistence Representation

- transport: artifact PubSub signals
- persistence: artifact state stored inside agent state and restored through checkpoints

### Compatibility Notes

- the canonical durable artifact value is the envelope data, not the UI's currently open panel state

## Task Update

### Owner

`jido_tasks`

### Producers

- human task creation and status changes
- agent actions that modify tasks

### Consumers

- task board UI
- Murmur task-assignment notification flow

### Canonical Shape

- task record with workspace ownership, assignee, and lifecycle status
- task-created and task-updated signals carrying the task payload

### Transport Or Persistence Representation

- transport: workspace task PubSub topics
- persistence: Ecto-backed task rows

### Compatibility Notes

- task assignment notifications are downstream consumers of this contract, not the source of truth for task state

## Persisted Thread Entry Replay

### Owner

The persisted entry format is owned by the Jido runtime and Murmur's replay boundary together.

### Producers

- Jido runtime and strategy pipeline while appending thread entries

### Consumers

- `ConversationReadModel.EntryProjector`
- thaw and reconnect flows

### Canonical Shape

Thread entries are not the canonical UI model. They are storage facts with fields such as:

- `kind`
- `payload`
- `refs`
- `seq`
- `at`

Murmur projects them into `ConversationReadModel` and `DisplayMessage`.

### Transport Or Persistence Representation

- persistence: PostgreSQL-backed thread-entry rows
- replay projection: normalized maps consumed by `EntryProjector`

### Compatibility Notes

- a persisted row format is not automatically the canonical contract for host apps
- when Murmur needs stable visible identity or ordering semantics beyond raw storage sequence, it carries that information in refs and re-projects it into the canonical read model