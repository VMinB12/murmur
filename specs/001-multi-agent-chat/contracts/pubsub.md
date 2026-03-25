# PubSub Contracts: Multi-Agent Chat Interface

**Feature**: `001-multi-agent-chat`  
**Date**: 2026-03-25

## Overview

All communication between backend `AgentServer` processes and the frontend `WorkspaceLive` LiveView uses `Phoenix.PubSub` (configured as `Murmur.PubSub`).

## Topic Format

```
"workspace:{workspace_id}:agent:{agent_session_id}"
```

- `workspace_id`: UUID of the workspace
- `agent_session_id`: UUID of the agent session (not the profile ID)

Each LiveView subscribes to one topic per active agent session upon mount.

## Message Payloads

### Token Streaming

Sent by the LLM execution Task during response generation.

```elixir
{:token, agent_session_id, message_id, token_string}
```

| Field | Type | Description |
|-------|------|-------------|
| agent_session_id | string (uuid) | Identifies which agent column to update |
| message_id | string (uuid) | Stable ID for the in-progress assistant message |
| token_string | string | The text chunk to append |

### Message Completed

Sent by the AgentServer when a complete agent turn finishes (all tool calls resolved, final assistant message ready).

```elixir
{:message_completed, agent_session_id, %Message{}}
```

| Field | Type | Description |
|-------|------|-------------|
| agent_session_id | string (uuid) | Identifies which agent session completed |
| Message | struct | The fully persisted `Murmur.Chat.Message` struct |

### Agent Status Change

Sent by the AgentServer when transitioning between idle and busy.

```elixir
{:status_change, agent_session_id, :idle | :busy}
```

| Field | Type | Description |
|-------|------|-------------|
| agent_session_id | string (uuid) | Identifies which agent's status changed |
| status | atom | `:idle` or `:busy` |

### New User/Inter-Agent Message

Sent by the AgentServer when a new user or inter-agent message is appended to history (before execution starts).

```elixir
{:new_message, agent_session_id, %Message{}}
```

| Field | Type | Description |
|-------|------|-------------|
| agent_session_id | string (uuid) | Identifies which agent received the message |
| Message | struct | The `Murmur.Chat.Message` struct (role: "user") |

## Subscription Lifecycle

1. **LiveView mount**: For each active `AgentSession` in the workspace, subscribe to `"workspace:{workspace_id}:agent:{agent_session_id}"`
2. **Agent added**: Subscribe to the new agent's topic
3. **Agent removed**: Unsubscribe from the removed agent's topic
4. **LiveView terminate**: Phoenix automatically unsubscribes on process death

## LiveView Handler Mapping

| PubSub Message | LiveView `handle_info` clause | UI Effect |
|----------------|-------------------------------|-----------|
| `{:token, ...}` | Update the in-progress message in the agent's stream | Append token text to the streaming message bubble |
| `{:message_completed, ...}` | Replace the streaming message with the final version via `stream_insert` | Finalize the message bubble |
| `{:status_change, ..., :busy}` | Update agent status assign | Show thinking/busy indicator |
| `{:status_change, ..., :idle}` | Update agent status assign | Hide thinking indicator |
| `{:new_message, ...}` | Insert new message into the agent's stream | Show the user/inter-agent message immediately |
