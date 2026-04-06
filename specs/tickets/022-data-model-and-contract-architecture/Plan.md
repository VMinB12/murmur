# Plan: Data Model And Contract Architecture

## Approach

Create two new focused architecture documents by synthesizing the current architecture docs and the recent tickets that established Murmur's canonical boundaries.

The intended end state is:

- `specs/Architecture/data-model.md` defines Murmur's major domain concepts, identity rules, relationships, read models, and important invariants
- `specs/Architecture/data-contracts.md` defines Murmur's important cross-boundary contracts, including ownership, producers, consumers, canonical shape, and transport or persistence representation
- `specs/Architecture/README.md` links to both documents
- related architecture docs reference the new documents where they currently describe only part of the same conceptual boundary

## Key Design Decisions

### 1. Separate domain model from boundary contracts

Do not mix conceptual entities and lifecycle rules with payload or transport definitions in one document.

Instead:

- `data-model.md` should describe canonical concepts such as workspaces, agent sessions, tasks, artifacts, conversations, and derived read models
- `data-contracts.md` should describe boundary shapes such as ingress input, visible message payloads, artifact updates, task updates, and persisted or replayed conversation shapes

### 2. Distinguish canonical shape from transport or persistence representation

When Murmur uses one canonical in-memory or conceptual shape but stores or transports it differently, the docs should say so explicitly.

This avoids repeating the kind of ambiguity that ticket 009 had to clean up around data contracts.

### 3. Prefer architectural synthesis over implementation dumps

The new docs should capture stable concepts and boundaries, not list every field from every struct or table.

They should be good guides for future contributors, not generated reference catalogs.

### 4. Reuse and cross-reference existing architecture docs

Do not duplicate detailed explanations that already live in `conversation-read-model.md`, `jido-murmur.md`, `jido-artifacts.md`, or `murmur-demo.md`.

Link outward where existing docs are already the better deep-dive.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| The new docs duplicate existing architecture material instead of clarifying it | Medium | Medium | Keep the new docs focused on canonical concepts and contracts, and cross-reference deeper topic docs instead of repeating them |
| The new docs become too implementation-specific | Medium | Medium | Avoid exhaustive field listings and focus on ownership, identity, lifecycle, and boundary semantics |
| Important contracts or invariants are missed | Medium | High | Review recent ADRs and tickets, especially those that changed actor identity, conversation projection, and contract enforcement |