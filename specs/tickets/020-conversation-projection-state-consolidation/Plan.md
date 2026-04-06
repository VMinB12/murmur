# Plan: Conversation Projection State Consolidation

## Approach

Move assistant-step assembly toward one shared canonical projection boundary and let `ConversationProjector` store full or fuller read-model state in ETS rather than only rendered messages.

The intended end state is:

- one shared assistant-step assembly surface is used by both live signal application and persisted-entry replay
- `ConversationProjector` can apply updates and reconciliation against canonical state instead of repeatedly reconstructing state from message lists
- snapshot callers can still request rendered messages, but the projector itself retains the richer underlying state needed for correctness and future cleanup

## Key Design Decisions

### 1. Consolidate the step assembler, not just helper names

Avoid a cosmetic refactor where duplicated lookup logic is simply moved around.

Instead, extract or centralize the actual assistant-step progression rule: when a new step starts, how a tool result attaches, and how a request continues versus opens a new step.

### 2. Cache the canonical state model in the projector

`ConversationProjector` currently stores only message lists in ETS. That keeps the read surface simple but throws away context that later updates and reconciliation need.

Store the canonical state model instead, and derive rendered messages from it at the boundary.

### 3. Preserve the ticket-017 behavior exactly

This is a structural cleanup ticket, not a behavior-change ticket. It should preserve assistant-step ordering, first-seen metadata, and nested tool-call rendering semantics.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Consolidation changes canonical behavior instead of only simplifying structure | Medium | High | Lock current behavior with regression tests before and after the refactor |
| Storing richer projector state in ETS creates more coupling to internal structs | Medium | Medium | Keep a narrow projector API that still returns rendered messages to callers |
| Replay and live-update paths still drift subtly even after refactor | Medium | High | Add paired tests that compare live reduction and replay for the same fixture conversation |