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

### The demo chat surface still carries a dead raw `ai.*` stream path

- `WorkspaceLive` no longer uses raw `ai.*` lifecycle signals as its rendering contract; it ignores them and renders only Murmur-owned canonical message updates.
- Despite that, the app still subscribes to the raw stream topic and `StreamingPlugin` still broadcasts the raw lifecycle signals over PubSub.
- That path now adds event traffic and cognitive overhead without contributing to chat correctness.
- That cleanup is worth doing, but it is orthogonal to the core freshness contract and is better tracked as a separate small ticket.

### The current code is close to the desired architecture, but one key contract is still missing

- The architecture docs already describe Murmur as having one canonical conversation projection model with snapshot loading plus canonical incremental updates.
- The current implementation is close to that shape: the projector caches the full `ConversationReadModel`, live `ai.*` lifecycle facts reduce into that model, and persisted replay also rebuilds that same model shape.
- The missing contract is explicit provenance and revision metadata on the cached model itself.
- Today the projector still has to infer whether cached state or source-derived state is newer by looking at empty versus non-empty models or by comparing message-level freshness heuristics.
- That means the system already behaves like a single-model architecture, but it does not yet encode the overwrite and reconciliation rules that would make that architecture explicit and durable.

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| Keep the current heuristic recovery logic as the long-term design | Minimal implementation cost and already fixes the user-visible bug | Leaves cache freshness implicit, keeps source precedence distributed across projector logic, and makes future regressions easier to reintroduce |
| Remove most caching and rebuild snapshots from runtime or persistence on every mount | Simplifies authority questions and reduces stale-cache risk | Likely throws away useful incremental state, increases mount cost, and weakens the current streaming model |
| Keep the cache as the single canonical read model, add explicit provenance and revision semantics, and split source-boundary cleanup plus raw `ai.*` removal into separate follow-up tickets | Preserves the current one-model architecture, removes heuristic overwrite rules, and avoids introducing a live-versus-persisted merge seam | Requires deliberate refactoring of projector metadata, reconciliation rules, and tests |

## Recommendation

Choose the third option.

Create an explicit conversation snapshot contract that answers these questions directly:

- what source produced the current snapshot
- what freshness or revision marker makes it newer than another source
- what precedence applies when runtime, persistence, and cache disagree
- what normalized entry shape the projector consumes regardless of source

The recommended simplification is not to delete the cache and not to split the product model into persisted-history state plus live overlay state. It is to keep the cache as the single canonical materialized `ConversationReadModel`, while adding explicit provenance and revision semantics so replay and live state can converge through declared rules rather than heuristic comparisons.

The projector should remain the owner of canonical conversation reduction. The related source-boundary cleanup is still valuable, but it is now tracked separately in ticket `026` so 024 can stay focused on the freshness contract itself.

## How This Differs From Today

The current architecture already looks superficially similar, which is why this ticket can be easy to misunderstand.

Today Murmur already has:

- one canonical `ConversationReadModel` shape
- one ETS-cached in-memory projector state
- one replay path that rebuilds that same model shape from persisted entries
- one live reduction path that applies `ai.*` lifecycle facts into that same model shape

What it does not yet have is:

- explicit metadata on the cached model that says what source produced it
- explicit revision semantics that say why one snapshot is newer than another
- explicit overwrite rules for when replayed persisted state may replace cached in-memory state
- a first-class contract for when reconciliation is allowed to keep the cache instead of replacing it

So the difference is not "switch from two models to one model." The difference is "make the existing one-model design explicit and provable instead of heuristic."

## Suggested Scope For The Follow-Up Ticket

- Define snapshot provenance metadata and revision semantics for the cached canonical `ConversationReadModel`.
- Define a single precedence policy for live projector state and replayed persisted state without splitting them into separate rendered models.
- Define explicit overwrite rules for when replayed persisted state may replace or confirm cached in-memory state.
- Add regression coverage for disagreement scenarios across runtime, replay, and cache sources beyond the specific empty-snapshot bug already fixed.
- Record the source-boundary cleanup and raw `ai.*` chat-path removal as separate tickets so 024 stays focused on freshness-contract semantics.
- Update architecture docs if the final design changes the documented conversation projection contract.

## References

- `specs/Architecture/README.md`
- `specs/Architecture/conversation-read-model.md`
- `specs/Architecture/data-contracts.md`
- `specs/tickets/020-conversation-projection-state-consolidation/`
- `specs/tickets/022-data-model-and-contract-architecture/`
- `specs/tickets/026-conversation-snapshot-source-boundary-cleanup/`
- `specs/tickets/027-remove-raw-ai-stream-chat-path/`
- `apps/jido_murmur/lib/jido_murmur/conversation_projector.ex`
- `apps/jido_murmur/lib/jido_murmur/conversation_read_model/replay_entry.ex`