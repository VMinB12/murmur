# Plan: Conversation Snapshot Source Boundary Cleanup

## Approach

Extract one dedicated boundary for sourcing replay-ready conversation entries and make `ConversationProjector` consume that boundary rather than discovering sources internally.

The intended end state is:

- `ConversationProjector` owns reduction and cached read-model updates
- a separate source boundary owns live-versus-offline entry retrieval
- offline conversation snapshots read persisted thread history directly rather than going through thaw

This keeps the canonical conversation model unchanged while making the read path easier to reason about and test.

## Key Design Decisions

### 1. Keep the canonical model unchanged

This ticket should not change `ConversationReadModel`, `DisplayMessage`, or top-level rendering semantics.

The goal is only to clean up where conversation entries come from before the projector reduces them.

### 2. Offline conversation history should use the narrowest viable boundary

If the snapshot path only needs replayable thread entries, it should read replayable thread entries directly.

Thaw should remain reserved for cases that genuinely need restored runtime state.

### 3. Preserve observable behavior

Live snapshot loading, offline snapshot loading, and completion reconciliation should continue to produce the same canonical messages they produce today.

This is a boundary cleanup ticket, not a behavior-change ticket.

## Data Model And Contract Impact

- No change to the canonical `ConversationReadModel` contract.
- No change to the `DisplayMessage` rendering contract.
- One new internal source boundary is introduced for replay-ready conversation entry retrieval.

## Risks And Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| The cleanup accidentally changes replayed snapshot behavior | Medium | High | Add parity tests for live and offline snapshots before and after the refactor |
| The new source boundary leaks projector concerns back into retrieval code | Medium | Medium | Keep the source boundary focused on entry retrieval and leave reduction in the projector |
| Direct thread loading misses normalization assumptions currently provided indirectly by thaw | Medium | High | Reuse the existing replay-normalization path and test persisted-entry fixtures explicitly |