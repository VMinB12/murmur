# Spec: Conversation Projection State Consolidation

## User Stories

### US-1: One assistant-step assembly rule (Priority: P1)

**As a** Murmur maintainer, **I want** live signal reduction and persisted-entry projection to share one assistant-step assembly rule, **so that** reconnect and refresh cannot drift from live behavior because the same concept is implemented twice.

**Independent test**: Run a multi-step assistant conversation through the live path and the storage-backed reconstruction path and verify both produce equivalent assistant-step segmentation and tool-call attachment.

### US-2: Richer projector state in core (Priority: P1)

**As a** Murmur maintainer, **I want** `ConversationProjector` to cache richer canonical read-model state than just rendered message lists, **so that** incremental updates and completion reconciliation do not have to rediscover step state from messages alone.

**Independent test**: Inspect the projector cache behavior and verify the cached state preserves enough canonical read-model information to apply incremental updates and reconciliation without reconstructing assistant-step progression from message lists only.

### US-3: Lower-cost future cleanup (Priority: P2)

**As a** Murmur maintainer, **I want** assistant-step projection logic to be located behind a small number of explicit modules, **so that** future ordering, tool-call, or replay changes do not require synchronized edits across several duplicate helpers.

**Independent test**: Inspect the canonical projection modules and verify step-boundary logic, step-index progression, and latest-step lookup live in a shared boundary rather than in duplicated private helpers across both live and persisted projection paths.

## Acceptance Criteria

- [ ] Assistant-step boundary and tool-result attachment rules are no longer duplicated independently across `apps/jido_murmur/lib/jido_murmur/conversation_read_model.ex` and `apps/jido_murmur/lib/jido_murmur/conversation_read_model/entry_projector.ex`.
- [ ] `apps/jido_murmur/lib/jido_murmur/conversation_projector.ex` caches richer canonical read-model state than a bare list of rendered messages.
- [ ] Snapshot loading, incremental signal application, and completion reconciliation operate on the same canonical state model.
- [ ] The consolidated design preserves the current assistant-step ordering and first-seen semantics established by ticket 017.
- [ ] Regression tests compare live reduction and storage-backed reconstruction for at least one multi-step request with tool activity.
- [ ] The cleanup does not reintroduce UI-owned ordering or request-level collapse behavior.
- [ ] Architecture documentation is updated if the projector state boundary or canonical module responsibilities change materially.

## Scope

### In Scope

- Consolidating assistant-step assembly logic inside canonical conversation modules
- Expanding projector cache state beyond rendered message lists
- Updating projector and read-model tests around replay and reconciliation
- Updating architecture docs if the module boundary changes materially

### Out of Scope

- Changing visible product semantics for ordering or assistant-step segmentation
- Reworking ingress ownership for user messages
- Redesigning chat rendering components