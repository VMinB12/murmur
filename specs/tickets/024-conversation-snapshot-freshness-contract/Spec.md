# Spec: Conversation Snapshot Freshness Contract

## User Stories

### US-1: Cached snapshots carry explicit freshness metadata (Priority: P1)

**As a** Murmur maintainer, **I want** the cached canonical `ConversationReadModel` to record its last source and persistence freshness markers, **so that** replay and refresh decisions do not depend on message-shape heuristics.

**Independent test**: Projector tests can assert the cached model records explicit source and live-advance metadata after visible ingress and streamed signal updates.

### US-2: Refresh preserves live-ahead cache state until persistence catches up (Priority: P1)

**As a** Murmur maintainer, **I want** remount and refresh paths to keep cache state that is ahead of live-thread replay, **so that** in-progress assistant updates and visible ingress messages are not silently clobbered.

**Independent test**: A cached live-advanced snapshot remains visible during refresh even when a source reload does not provide a newer persisted revision.

### US-3: Reconciliation uses declared revision rules (Priority: P1)

**As a** Murmur maintainer, **I want** completion-time replay confirmation to replace cache state only when the persisted revision advances, **so that** overwrite behavior is explained by contract instead of heuristics.

**Independent test**: Projector reconciliation preserves cached state for empty or stale replay results and accepts replayed state once persistence has advanced.

## Acceptance Criteria

- [x] The canonical cached `ConversationReadModel` records explicit source provenance and persistence freshness metadata.
- [x] Visible ingress insertion and streamed signal reduction advance the cached model through explicit live-side metadata rather than implicit message-shape comparisons.
- [x] Snapshot refresh no longer relies on content-weight or message-shape heuristics to decide whether cache or replay wins.
- [x] Completion reconciliation replaces cache state only when replayed persisted revision metadata proves the replay is newer.
- [x] Focused regression tests cover the new freshness contract for cached snapshots.

## Scope

### In Scope

- canonical snapshot provenance metadata
- persisted revision semantics for replay-built models
- live-advance semantics for visible ingress and streamed signal updates
- projector freshness rules for refresh and reconciliation

### Out of Scope

- direct source-boundary extraction mechanics tracked by ticket `026`
- raw `ai.*` chat transport cleanup tracked by ticket `027`
- changing the canonical `DisplayMessage` rendering contract