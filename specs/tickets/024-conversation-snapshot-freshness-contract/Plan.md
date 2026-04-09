# Plan: Conversation Snapshot Freshness Contract

## Approach

Keep one canonical `ConversationReadModel` everywhere and make its freshness contract explicit.

The intended end state is:

- the projector cache remains the canonical materialized in-memory `ConversationReadModel`
- live signal application and persisted replay continue to converge on that same model shape
- cached projector state carries explicit provenance and revision semantics
- snapshot serving and reconciliation use declared overwrite rules instead of message-shape heuristics

This keeps the user-facing refresh and reconnect behavior that the cache currently enables without introducing a second persisted-versus-live rendering seam.

## Key Design Decisions

### 1. Keep one canonical read model, not a persisted-history plus live-overlay split

The stronger simplification is not to split the product model into two concurrently rendered halves.

- Murmur already has one canonical `ConversationReadModel` shape today.
- Live signal application and replayed persisted entries already target that same model shape.
- Introducing a separate persisted-history model plus live overlay would create a new merge seam and a new class of ordering or duplication bugs.

This ticket should strengthen the existing one-model direction rather than replace it.

### 2. The cache remains the canonical materialized in-memory state

The ETS cache should not be described as a disposable optimization layer.

It is the current materialized read model that lets Murmur:

- accumulate streamed assistant-step state incrementally
- preserve immediate visible ingress ordering and identity
- serve reconnect and refresh snapshots without rebuilding from scratch on every update

What changes in this ticket is not the existence of the cache, but the explicit contract around when it is considered current and when replay may replace or confirm it.

### 3. Persisted thread entries remain the durability and rebuild source

Persisted thread entries are still the durable conversation log.

They should be able to rebuild the canonical `ConversationReadModel`, but that does not mean the product architecture should treat replayed history as a separately rendered state model.

The important contract is:

- persisted replay can reconstruct the canonical model
- cached in-memory state can advance the canonical model between rebuilds
- explicit revision rules determine when replay supersedes or confirms cache state

### 4. Make provenance and revision explicit instead of heuristic

The current freshness guards are still heuristic because they infer "newer" from message content, ordering metadata, and shape comparisons.

This ticket should define explicit metadata for the cached canonical model, such as:

- what source last produced or confirmed the cached model
- what persisted revision the cached model is known to include
- what live updates have advanced the cached model since that persisted revision
- what rule allows replayed state to replace or confirm the cached model

The goal is that cache-versus-replay choices are explained by contract, not by empty-state checks or content-weight heuristics.

### 5. Keep 024 focused on freshness semantics

Two useful cleanups are related but separate:

- projector source-boundary cleanup and thaw removal from the snapshot path
- dead raw `ai.*` chat-path removal

Those are both worth doing, but they are implementation-focused cleanup tickets rather than the core architectural question of what makes one cached snapshot newer or more authoritative than another.

They should be tracked separately so 024 can answer the central contract question cleanly.

## How This Differs From The Current Architecture

The current architecture already claims most of the high-level shape that this ticket wants:

- one canonical conversation read model
- one projector-backed snapshot path
- one live canonical update path

What is still missing today is the contract that makes that design robust:

- the cached model does not carry first-class provenance metadata
- the cached model does not carry explicit persisted-revision semantics
- reconciliation still needs heuristic comparison to decide whether replay or cache wins
- overwrite rules are encoded indirectly in recovery behavior rather than explicitly in the model contract

So this ticket does not change the architectural shape as much as it tightens and formalizes what the current architecture only implies.

## Suggested Implementation Phases

### Phase 1. Define cached-model provenance and revision semantics

- Define what metadata the cached canonical model must carry.
- Decide how persisted revision, live advancement, and source provenance are represented.
- Document the invariants those markers must satisfy.

### Phase 2. Apply the new metadata at all canonical write points

- Update live signal application and visible-ingress insertion so cached state advances through explicit metadata.
- Update completion reconciliation so replay confirmation or replacement follows declared rules.

### Phase 3. Replace heuristic freshness checks with contract-driven reconciliation

- Remove content-shape heuristics as the primary decision maker for replay versus cache.
- Keep or retain heuristics only as defensive fallback if truly necessary.

### Phase 4. Document and lock the invariants with tests

- Add projector and refresh regressions that cover disagreement between cached state and replayed persisted state.
- Update architecture docs so the one-model design and its overwrite rules are explicit.

## Risks And Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Revision metadata is added but still too weak to eliminate heuristic overwrite rules | Medium | High | Treat overwrite semantics as a first-class deliverable, not as an implementation detail |
| The ticket drifts back into source-boundary cleanup and stops being about freshness semantics | Medium | Medium | Keep tickets `026` and `027` separate and let 024 reference them rather than absorbing them |
| The stronger contract changes hidden assumptions in projector tests or replay behavior | Medium | High | Add explicit disagreement and reconciliation tests before removing the current heuristics |