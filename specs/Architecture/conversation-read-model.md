# Conversation Read Model

## Purpose

This document defines Murmur's canonical conversation projection model for chat rendering.

See [data-model.md](data-model.md) for where the conversation read model sits relative to Murmur's other entities, and [data-contracts.md](data-contracts.md) for the connected-client and replay contracts that carry this model.

It answers one question: how does Murmur keep live in-progress assistant steps, refreshed history, and reconnect state consistent without asking the UI to reconstruct meaning from raw `ai.*` lifecycle signals?

## Problem

Before ticket 016, Murmur had two different rendering paths:

- a live path where `WorkspaceLive` reduced raw `ai.llm.delta`, `ai.llm.response`, `ai.tool.result`, and `ai.usage` signals into an ad hoc `%{content, thinking, tool_calls, usage}` map
- a refresh path where Murmur reloaded thread entries and projected them through a separate request-level adapter

That made the UI vulnerable to ordering differences between topics and left refreshed history richer than the live view.

Ticket 017 exposed a second problem: Murmur was still treating one outer ReAct request as one assistant message. That was too coarse for steering and `tell` ordering because a single outer request can contain several LLM/tool phases.

## Core Rule

`jido_murmur` owns the canonical conversation state.

The frontend no longer treats raw `ai.*` signals as the rendering contract. Instead, Murmur reduces those raw facts into canonical top-level message state and emits Murmur-owned conversation updates.

The canonical assistant message is now an assistant step:

- one LLM invocation
- plus the tool calls and tool results produced before the next LLM invocation or request completion

## High-Level Flow

### 1. Initial snapshot

When a UI mounts or reconnects, it loads a conversation snapshot for each session from the core-owned projector boundary.

That snapshot is derived from:

- live thread state when the agent is running
- persisted thread history read directly from storage when the agent is not live
- any in-memory projector state that represents the current in-progress assistant step sequence

Before persisted or thawed thread entries are projected, Murmur first normalizes replay-only storage and runtime entry shapes through a dedicated replay adapter boundary. The canonical projector then works against that normalized replay shape instead of embedding storage-shape cleanup directly into assistant-step projection rules.

The projector cache now stores the full canonical `ConversationReadModel`, not only the rendered message list, so snapshot load and incremental updates reuse the same assistant-step state.

The cached read model also carries explicit freshness metadata:

- the last source that confirmed or advanced the model
- the persisted thread revision known to be included
- the live-side revision count that has advanced the cache beyond that persisted baseline

Snapshot refresh keeps live-ahead cache state over live-thread replay, while completion reconciliation only replaces the cache once persisted revision metadata proves replay is newer.

### 2. Incremental canonical updates

While a run is active, Murmur still receives low-level lifecycle facts such as:

- `ai.llm.delta`
- `ai.llm.response`
- `ai.tool.started`
- `ai.tool.result`
- `ai.usage`
- `murmur.message.completed`

Those are reduced inside the core package into canonical assistant-step messages. One outer `request_id` may therefore yield multiple assistant messages over time.

The UI receives Murmur-owned conversation updates for the affected top-level message rather than reducing raw lifecycle signals itself.

### 3. Completion reconciliation

When a run completes, finalized thread-backed history reconciles through the same canonical projection boundary rather than becoming a second richer rendering path.

This means the live UI and refreshed UI answer the same question:

- what is the current canonical top-level conversation state for this session?

## Identity Model

### Session identity

`session.id` identifies the agent session.

### Turn identity

`request_id` identifies one outer run.

### Assistant-step identity

Murmur owns assistant-step identity inside that outer run. A single `request_id` may map to `step-1`, `step-2`, and later assistant-step messages as the ReAct loop continues.

### Tool identity

`tool_call_id` identifies one tool lifecycle within an assistant step.

The projector must attach or preserve these identities so that late or out-of-order facts can still merge into the correct assistant step.

## Ordering Model

Top-level conversation messages are ordered by Murmur-owned first-seen metadata.

- human and `tell` messages remain top-level user messages
- assistant messages are ordered assistant steps
- tool calls and tool results remain nested inside the assistant step that produced them

This keeps the visible model aligned with what later steering can influence without promoting every sub-element into its own top-level timeline item.

## Transport Model

The UI contract is:

- full snapshot on mount or reconnect
- canonical incremental top-level message updates while connected

It is intentionally **not**:

- full conversation snapshot on every token
- raw `ai.*` lifecycle stream as the rendering protocol

The older raw `ai.*` chat PubSub path has been removed from the demo surface, so canonical conversation updates are now the only chat-rendering transport contract.

This keeps rendering ownership centralized without forcing large full-state payloads on every small text update.

## Performance Model

The browser still re-renders the currently active turn as content grows, which is unavoidable for streamed text in LiveView.

However, Murmur avoids the worst architectural form of duplication by:

- centralizing assistant-step reduction in the core package
- sending only the affected canonical message update during streaming
- loading the full snapshot only on mount or reconnect

If token frequency becomes too high later, batching or coalescing can be added at the projector boundary without changing the UI contract.

## Ownership Boundaries

### `jido_murmur`

- owns conversation reduction
- owns assistant-step identity and first-seen ordering attachment
- owns projector-backed snapshots
- owns the Murmur conversation update contract
- owns the replay normalization adapter that translates Jido or storage entry shapes into replay-ready projector input

### `jido_murmur_web`

- owns generic rendering primitives for canonical top-level message state
- does not own reduction of raw agent lifecycle facts

### `murmur_demo`

- subscribes to Murmur-owned conversation updates
- renders projector-backed snapshots
- keeps screen-level orchestration and demo-specific UX concerns

## Result

Murmur no longer has a live rendering path and a separate refresh rendering path.

It has one canonical conversation projection model with two access modes:

- snapshot loading
- canonical incremental updates

That is the architectural change that removes the split.