# Spec: Conversation Snapshot Source Boundary Cleanup

## User Stories

### US-1: Projector reduces canonical inputs only (Priority: P1)

**As a** Murmur maintainer, **I want** `ConversationProjector` to receive replay-ready conversation inputs from a dedicated source boundary, **so that** projection logic and source-discovery logic do not drift together.

**Independent test**: Snapshot loading and reconciliation still return the same canonical messages for live-session and offline-session fixtures after source discovery is moved out of the projector.

### US-2: Offline history loads without runtime restore coupling (Priority: P1)

**As a** Murmur maintainer, **I want** offline conversation snapshots to read persisted thread history directly, **so that** the conversation read side does not depend on full agent thaw when it only needs replayable entries.

**Independent test**: A stopped session with persisted thread history can still produce the expected snapshot without relying on thaw-based conversation recovery inside `ConversationProjector`.

### US-3: Non-conversation thaw paths remain unchanged (Priority: P2)

**As a** Murmur maintainer, **I want** agent startup and artifact loading behavior to remain unchanged, **so that** this cleanup stays small and does not widen into unrelated runtime refactors.

**Independent test**: Existing agent start and artifact-loading behavior remains unchanged in focused tests after the conversation snapshot cleanup lands.

## Acceptance Criteria

- [x] `ConversationProjector` no longer performs ad hoc live-process lookup and thaw-driven offline history recovery internally for snapshot loading and reconciliation.
- [x] The conversation snapshot path uses one dedicated source boundary that returns replay-ready entry data for live and offline sessions.
- [x] Offline conversation snapshot reconstruction reads persisted thread history directly rather than thawing a full agent only to extract thread entries.
- [x] Canonical `ConversationReadModel` and `DisplayMessage` behavior remain unchanged for live and offline snapshots.
- [x] Existing thaw-based behavior outside the conversation snapshot path remains out of scope and unchanged.

## Scope

### In Scope

- conversation snapshot source selection
- direct offline thread-history loading for conversation snapshots
- projector cleanup needed to consume the new source boundary
- focused regression coverage for live and offline snapshot parity

### Out of Scope

- changing the canonical `ConversationReadModel` shape
- changing freshness or revision semantics tracked by ticket `024`
- artifact loading changes
- agent boot or runtime restore redesign