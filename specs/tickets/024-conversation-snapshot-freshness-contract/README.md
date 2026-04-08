---
id: "024"
title: "Conversation Snapshot Freshness Contract"
status: research
jira: ""
owner: ""
created: 2026-04-08
updated: 2026-04-08
---

# 024 — Conversation Snapshot Freshness Contract

Formalize the canonical freshness and source-of-truth rules for Murmur conversation snapshots so the projector cache cannot silently diverge from runtime or persisted history. This follow-up ticket exists because the refresh and replay bug was fixed successfully, but the underlying projector lifecycle still relies on heuristic recovery paths instead of an explicit freshness contract between live thread state, replayed persisted entries, and ETS-cached `ConversationReadModel` values.