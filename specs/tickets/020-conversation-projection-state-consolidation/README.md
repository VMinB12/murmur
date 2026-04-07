---
id: "020"
title: "Conversation Projection State Consolidation"
status: done
jira: ""
owner: ""
created: 2026-04-06
updated: 2026-04-07
---

# 020 — Conversation Projection State Consolidation

Consolidate assistant-step assembly and projector state so live signal reduction and persisted-entry reconstruction share one canonical step-projection rule, and `ConversationProjector` caches richer read-model state instead of only storing rendered message lists in ETS.

Implemented on 2026-04-07. `ConversationProjector` now caches the full `ConversationReadModel`, replay flows through the same read-model APIs as live updates, and the old message-list snapshot compatibility path has been removed.