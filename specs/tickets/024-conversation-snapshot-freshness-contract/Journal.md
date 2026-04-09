# Journal

## 2026-04-08

- Resumed the ticket after fixing the refresh regression that exposed the current snapshot-freshness ambiguity.
- Confirmed the recommended direction is to keep the cache rather than remove it, because it still carries live canonical read-model state during streaming and immediate visible-ingress reconciliation.
- Updated the ticket to plan around a narrower cache contract, explicit freshness markers, a dedicated snapshot-source boundary, and removal of the dead `ai.*` UI rendering path.

## 2026-04-09

- Revisited the architectural direction after reviewing whether a persisted-history plus live-overlay split would actually simplify the system.
- Narrowed the recommendation to a stronger one-model design: keep the cache as the canonical materialized `ConversationReadModel` and make provenance plus revision semantics explicit.
- Split the source-boundary cleanup and raw `ai.*` chat-path removal into separate tickets `026` and `027` so 024 can stay focused on the freshness contract itself.