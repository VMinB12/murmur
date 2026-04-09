# Tasks: Conversation Snapshot Freshness Contract

## P1: Freshness Contract

- [x] T001 Extend the canonical `ConversationReadModel` with explicit source provenance and persisted freshness metadata.
- [x] T002 Advance cached snapshot metadata explicitly for visible ingress and streamed signal updates.
- [x] T003 Replace heuristic snapshot overwrite logic in `ConversationProjector` with declared refresh and reconciliation rules.
- [x] T004 Add focused regression coverage for cached freshness metadata and refresh behavior.
- [x] T005 Update architecture docs and changelog entries for the new snapshot freshness contract.