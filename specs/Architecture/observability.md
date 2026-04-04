# Observability

## Purpose

This document defines Murmur's current observability model for:

- root trace boundaries
- Phoenix session grouping
- cross-agent workflow correlation
- direct-chat discussion lifecycle

It documents the shipped runtime behavior for ticket 010.

## Core Terms

### Agent Session

An agent session is the long-lived runtime identity of one agent process.

Examples:

- Alice's agent session id
- Bob's agent session id

This is exported as `murmur.agent_id`.

It identifies the concrete agent that executed a turn.

It does **not** define the Phoenix session grouping model.

### Turn

A turn is one executed react loop in `Runner`.

One turn produces:

- one root `AGENT` span
- zero or more child `LLM` spans
- zero or more child `TOOL` spans

The request id for that root turn is exported as `murmur.request_id`.

### Discussion

A discussion is the grouping unit Murmur uses for Phoenix Sessions.

It is represented by `murmur.interaction_id` and copied into `session.id` on exported spans.

A discussion is **not** the same thing as:

- an agent session lifetime
- a workspace lifetime
- a whole team's activity

Instead, it means "the current related exchange of work that should appear as one Phoenix session row."

### Workspace Correlation

`murmur.workspace_id` is the workspace/team correlation key.

It is used for filtering and cross-trace analysis, but it is **not** the Phoenix session grouping key.

## IDs And Their Roles

| Field | Meaning | Scope |
|---|---|---|
| `murmur.agent_id` | Concrete executing agent session id | One agent runtime |
| `murmur.request_id` | One executed react loop | One turn |
| `murmur.interaction_id` | Discussion or workflow correlation id | One discussion/workflow |
| `session.id` | Phoenix Sessions grouping key | Same value as current discussion id |
| `murmur.workspace_id` | Workspace/team correlation id | One workspace |

## Session Grouping Rule

Phoenix Sessions groups traces by `session.id`.

Murmur therefore exports `session.id` as the current discussion id, not the long-lived agent id.

The runtime rule is:

1. Determine the `interaction_id` for the batch of messages being processed.
2. Export that id as both `murmur.interaction_id` and `session.id`.
3. Keep `murmur.agent_id` as the concrete agent that executed the turn.

This happens in `Runner.process_batch/2`.

## Why ConversationCache Exists

Cross-agent workflows already have a natural discussion id: the sender can propagate one explicitly.

Direct human chat does not.

That created two bad alternatives:

1. Mint a new interaction id for every direct message.
This made one human conversation appear as multiple Phoenix sessions.

2. Reuse the agent session id forever.
This made unrelated future chats collapse into one old Phoenix session row tied to that agent.

`ConversationCache` exists to give direct chat a stable, discussion-scoped id without turning the agent lifetime into the discussion lifetime.

## Current Discussion Definition

The definition depends on how the work was started.

### Direct User Chat

For direct chat, a discussion is:

- all direct messages sent to the same agent session
- while that chat remains active
- until the inactivity timeout expires

The cache key is the receiving agent session id.

The cached value is the current discussion `interaction_id` for that agent's direct chat.

This means direct-chat discussions are effectively per-agent, not per-workspace.

That is intentional: a conversation with Alice and a separate conversation with Bob should not be grouped together unless some workflow explicitly links them.

### Cross-Agent Or Workflow Messages

For non-direct messages, the runtime prefers an explicit propagated `interaction_id`.

That means a multi-agent workflow can share one discussion id across multiple agents and multiple turns.

In that case, the discussion is **not** tied to one agent. It is tied to the workflow or interaction being propagated through the system.

## What Starts A Discussion

### Direct Chat Start

A new direct-chat discussion starts when a direct message is sent to an agent session and there is no still-active cached discussion for that agent.

That happens in either of these cases:

- this is the first direct message to that agent in the current runtime
- the prior direct discussion expired by inactivity
- the cache was explicitly cleared during cleanup/reset

When that happens, Murmur generates a fresh `interaction_id`.

### Workflow Discussion Start

A new workflow discussion starts when work enters the system without an explicit `interaction_id` and is not a direct-chat reuse case.

If a caller already supplies an `interaction_id`, that caller is defining the workflow discussion explicitly.

## What Ends A Discussion

For direct chat, a discussion ends when one of these happens:

1. Inactivity timeout expires.
2. Session/workspace cleanup deletes the cached discussion entry.
3. A reset or agent teardown removes the cached association.

For propagated cross-agent workflows, Murmur does not impose a separate workflow-end event. The workflow discussion simply continues for as long as new work keeps using the same propagated `interaction_id`.

## Inactivity Timeout

Yes. There is a timeout.

`ConversationCache` uses `:conversation_session_timeout_ms` from the `:jido_murmur` application env.

Current shipped behavior:

- default timeout: `:timer.minutes(1)`
- current app config override: none
- tests explicitly set it to `60_000` ms to validate rollover behavior

So in practice the current default inactivity window is **one minute**.

If a second direct message reaches the same agent within one minute of the previous direct message for that agent, it reuses the same discussion id.

If it arrives after that inactivity window, Murmur starts a new discussion id and Phoenix will show a new session row.

## Runtime Resolution Rules

`ConversationCache.resolve/2` currently behaves like this:

### Non-direct message

- if `interaction_id` is provided: use it
- otherwise: mint a new interaction id

### Direct message with explicit `interaction_id`

- use that explicit id
- refresh the cache for the receiving agent session

### Direct message without explicit `interaction_id`

- if cached discussion is still active: reuse cached id
- otherwise: mint a new interaction id

## Examples

### Example 1: Two direct messages to Alice

User sends `hello` to Alice.

- no cached direct discussion exists
- Murmur creates interaction `I-1`
- exported `session.id = I-1`

Ten seconds later the user sends `can you expand on that?` to Alice.

- cached discussion `I-1` is still active
- Murmur reuses `I-1`
- both traces appear in one Phoenix session

### Example 2: Later direct message to Alice after inactivity

User talks to Alice again after more than one minute.

- cached discussion is considered inactive
- Murmur creates interaction `I-2`
- Phoenix shows a new session row

### Example 3: Alice tells Bob to do work

Alice starts a workflow using interaction `I-3`.

Bob receives work with propagated `interaction_id = I-3`.

- Bob creates a new root turn trace for his own react loop
- Bob still exports `session.id = I-3`
- Alice and Bob traces appear under one Phoenix session

## Final Model

The final shipped model is:

- one root trace per executed react loop
- one Phoenix session per discussion/workflow
- direct chat discussions are per-agent and inactivity-bounded
- cross-agent workflows are grouped by explicitly propagated interaction id
- workspace/team identity is separate correlation metadata, not the session grouping key

## Operational Notes

`ConversationCache` is runtime state stored in ETS.

It is created by `TableOwner` and cleared when workspace or agent storage is explicitly cleaned up.

It should be treated as ephemeral coordination state, not persisted conversation history.

## Related Modules

- `JidoMurmur.Runner`
- `JidoMurmur.Observability`
- `JidoMurmur.Observability.ConversationCache`
- `JidoMurmur.Observability.Store`
- `JidoMurmur.TableOwner`
- `JidoMurmur.AgentHelper`
- `MurmurWeb.WorkspaceLive`