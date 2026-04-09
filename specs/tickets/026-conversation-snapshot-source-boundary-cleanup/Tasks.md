# Tasks: Conversation Snapshot Source Boundary Cleanup

## P1: Projector Source Cleanup

- [x] T001 Add a dedicated conversation snapshot-source boundary that can return replay-ready entries for a session from live runtime state or persisted thread history.
- [x] T002 Update `apps/jido_murmur/lib/jido_murmur/conversation_projector.ex` to consume the new source boundary instead of performing source discovery internally.
- [x] T003 Update the offline conversation snapshot path to read persisted thread history directly rather than thawing a full agent only to recover thread entries.
- [x] T004 Add or update focused tests under `apps/jido_murmur/test/jido_murmur/` and `apps/murmur_demo/test/murmur_web/live/` to verify live and offline snapshot parity and unchanged canonical message output.
- [x] T005 Run focused tests for the touched conversation-projector, snapshot-loading, and persistence files, then run `mix precommit` from `/Users/vincent.min/Projects/murmur`.