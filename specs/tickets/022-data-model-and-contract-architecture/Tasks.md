# Tasks: Data Model And Contract Architecture

## Task List

Format: `- [ ] T001 [P] Description with file path`
- **T001, T002, …** — sequential task ID
- **[P]** — present only when the task can run in parallel with others
- Include the exact file path to create or modify in the description

### P1 — Canonical Data Model And Contract Docs

- [ ] T001 Audit the current architecture and recent spec history in `specs/Architecture/README.md`, `specs/Architecture/conversation-read-model.md`, `specs/Architecture/jido-murmur.md`, `specs/Architecture/jido-artifacts.md`, `specs/Architecture/murmur-demo.md`, `specs/tickets/009-data-contract-enforcement/`, and `specs/tickets/017-canonical-conversation-message-ordering/` to extract Murmur's canonical entities, read models, and boundary contracts.
- [ ] T002 Create `specs/Architecture/data-model.md` documenting Murmur's major domain entities, identities, relationships, read models, and architectural invariants.
- [ ] T003 Create `specs/Architecture/data-contracts.md` documenting Murmur's important cross-boundary contracts with owner, producer, consumer, canonical shape, and transport or persistence representation.
- [ ] T004 Update `specs/Architecture/README.md` to link to `specs/Architecture/data-model.md` and `specs/Architecture/data-contracts.md`.

### P2 — Cross-References And Consistency

- [ ] T005 [P] Update `specs/Architecture/conversation-read-model.md`, `specs/Architecture/jido-murmur.md`, `specs/Architecture/jido-artifacts.md`, and `specs/Architecture/murmur-demo.md` where needed so the new documents are referenced and no contradictory definitions remain.
- [ ] T006 Verify the new docs stay aligned with `specs/tickets/009-data-contract-enforcement/`, `specs/decisions/ADR-004-canonical-actor-identity-and-display-boundary.md`, and `specs/decisions/ADR-007-explicit-first-seen-conversation-message-ordering.md`, then update wording if those sources expose any drift.

## Completion Criteria

All acceptance criteria from `Spec.md` are satisfied, Murmur's architecture now has first-class `data-model.md` and `data-contracts.md` documents, and the architecture index plus relevant sub-documents point contributors to those canonical references instead of leaving the concepts fragmented across tickets.