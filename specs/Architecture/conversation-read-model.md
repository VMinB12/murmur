# Conversation Read Model

## Purpose

This document defines Murmur's canonical conversation projection model for chat rendering.

It answers one question: how does Murmur keep live in-progress turns, refreshed history, and reconnect state consistent without asking the UI to reconstruct meaning from raw `ai.*` lifecycle signals?

## Problem

Before ticket 016, Murmur had two different rendering paths:

- a live path where `WorkspaceLive` reduced raw `ai.llm.delta`, `ai.llm.response`, `ai.tool.result`, and `ai.usage` signals into an ad hoc `%{content, thinking, tool_calls, usage}` map
- a refresh path where Murmur reloaded thread entries and projected them into richer display messages through `UITurn`

That made the UI vulnerable to ordering differences between topics and left refreshed history richer than the live view.

## Core Rule

`jido_murmur` owns the canonical conversation state.

The frontend no longer treats raw `ai.*` signals as the rendering contract. Instead, Murmur reduces those raw facts into canonical turn state and emits Murmur-owned conversation updates.

## High-Level Flow

### 1. Initial snapshot

When a UI mounts or reconnects, it loads a conversation snapshot for each session from the core-owned projector boundary.

That snapshot is derived from:

- live thread state when the agent is running
- thawed persisted thread state when the agent is not live
- any in-memory projector state that represents the current in-progress turn

### 2. Incremental canonical updates

While a run is active, Murmur still receives low-level lifecycle facts such as:

- `ai.llm.delta`
- `ai.llm.response`
- `ai.tool.started`
- `ai.tool.result`
- `ai.usage`
- `murmur.message.completed`

Those are reduced inside the core package into one canonical assistant turn identified by a stable `request_id`.

The UI receives Murmur-owned conversation updates for the affected turn rather than reducing raw lifecycle signals itself.

### 3. Completion reconciliation

When a run completes, finalized thread-backed history reconciles through the same canonical projection boundary rather than becoming a second richer rendering path.

This means the live UI and refreshed UI answer the same question:

- what is the current canonical visible turn state for this session?

## Identity Model

### Session identity

`session.id` identifies the agent session.

### Turn identity

`request_id` identifies one assistant turn or run.

### Tool identity

`tool_call_id` identifies one tool lifecycle within a turn.

The projector must attach or preserve these identities so that late or out-of-order facts can still merge into the correct turn.

## Transport Model

The UI contract is:

- full snapshot on mount or reconnect
- canonical incremental turn updates while connected

It is intentionally **not**:

- full conversation snapshot on every token
- raw `ai.*` lifecycle stream as the rendering protocol

This keeps rendering ownership centralized without forcing large full-state payloads on every small text update.

## Performance Model

The browser still re-renders the currently active turn as content grows, which is unavoidable for streamed text in LiveView.

However, Murmur avoids the worst architectural form of duplication by:

- centralizing turn reduction in the core package
- sending only the affected canonical turn update during streaming
- loading the full snapshot only on mount or reconnect

If token frequency becomes too high later, batching or coalescing can be added at the projector boundary without changing the UI contract.

## Ownership Boundaries

### `jido_murmur`

- owns conversation reduction
- owns stable turn identity attachment
- owns projector-backed snapshots
- owns the Murmur conversation update contract

### `jido_murmur_web`

- owns generic rendering primitives for canonical message or turn state
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