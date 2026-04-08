# Research: Conversation Snapshot Freshness Contract

## Objective

Define the architectural follow-up needed after the refresh and replay bug fix so Murmur has an explicit, durable contract for how conversation snapshots are sourced, cached, refreshed, and reconciled across runtime thread state, persisted replay, and reconnect or remount flows.

## Findings

### The shipped fix corrected real defects, but it also exposed an under-specified cache boundary

- The recent bug was not only a missing local update; it also showed that `ConversationProjector` was treating an ETS snapshot as if it were authoritative without a formal freshness rule.
- The implementation now recovers from stale empty snapshots and avoids clobbering a good cached model with an empty reconcile result, which is correct behavior for the bug at hand.
- Those guards are still heuristic because the projector does not carry explicit freshness or revision metadata that can prove whether cache, runtime thread, or persisted replay is newer.

### Murmur currently has three conversation-state sources with no declared precedence contract

- A mounted UI can derive conversation state from live runtime thread state when an agent is running.
- A reconnect or cold recovery path can derive conversation state from persisted thread entries.
- The projector also maintains an ETS-cached `ConversationReadModel` for incremental canonical updates.
- The architecture docs correctly say `jido_murmur` owns the canonical conversation model, but they do not yet define a precise precedence policy when those three sources disagree or one source is present but empty.

### Empty state is especially ambiguous without explicit freshness semantics

- The bug reproduced because an empty cached `ConversationReadModel` could mask valid runtime or persisted conversation history.
- The current recovery logic uses emptiness as a signal to attempt refresh from source or storage.
- That is a sound operational safeguard, but empty state should not need to act as a proxy for stale state if the boundary is formally modeled.

### The projector still knows too much about how entries are sourced

- `ConversationProjector` owns canonical reduction, which is the right responsibility.
- It also still participates directly in pulling and reconciling entry collections from runtime or persisted shapes.
- That means freshness policy, source selection, replay normalization, and projection behavior are not yet separated as cleanly as the architecture suggests.
- A more durable design would let the projector consume one normalized entry source contract plus freshness metadata rather than embedding source-recovery heuristics inside projection behavior.

### Replay normalization is the right pattern and should probably be pushed one step further

- The replay bug was fixed by normalizing persisted string keys for visible-message identity and ordering refs before projection.
- That fix reinforces the existing architecture direction: storage shape should not be treated as the canonical in-memory contract.
- The next architectural step is to make all snapshot-building inputs arrive through one explicit normalized boundary, regardless of whether the entries originated from live thread state or persisted replay.

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| Keep the current heuristic recovery logic as the long-term design | Minimal implementation cost and already fixes the user-visible bug | Leaves cache freshness implicit, keeps source precedence distributed across projector logic, and makes future regressions easier to reintroduce |
| Remove most caching and rebuild snapshots from runtime or persistence on every mount | Simplifies authority questions and reduces stale-cache risk | Likely throws away useful incremental state, increases mount cost, and weakens the current streaming model |
| Add an explicit snapshot-source contract with freshness metadata and normalized entry sourcing | Clarifies authority, makes cache semantics testable, and aligns implementation with the documented canonical-boundary architecture | Requires deliberate refactoring across projector, replay, and snapshot-loading paths |

## Recommendation

Choose the third option.

Create an explicit conversation snapshot contract that answers these questions directly:

- what source produced the current snapshot
- what freshness or revision marker makes it newer than another source
- what precedence applies when runtime, persistence, and cache disagree
- what normalized entry shape the projector consumes regardless of source

The projector should remain the owner of canonical conversation reduction, but it should consume a clearer source boundary instead of mixing reduction behavior with source-selection heuristics. That would make the current bug fix durable instead of merely defensive.

## Suggested Scope For The Follow-Up Ticket

- Define snapshot freshness metadata or revision semantics for cached conversation read models.
- Define a single precedence policy for runtime thread state, persisted replay, and cached projector state.
- Introduce or strengthen a normalized entry-sourcing boundary so the projector does not need to know whether entries came from live thread internals or persisted storage.
- Add regression coverage for disagreement scenarios across runtime, replay, and cache sources beyond the specific empty-snapshot bug already fixed.
- Update architecture docs if the final design changes the documented conversation projection contract.

## References

- `specs/Architecture/README.md`
- `specs/Architecture/conversation-read-model.md`
- `specs/Architecture/data-contracts.md`
- `specs/tickets/020-conversation-projection-state-consolidation/`
- `specs/tickets/022-data-model-and-contract-architecture/`
- `apps/jido_murmur/lib/jido_murmur/conversation_projector.ex`
- `apps/jido_murmur/lib/jido_murmur/conversation_read_model/replay_entry.ex`