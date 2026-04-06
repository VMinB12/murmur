---
id: "020"
title: "Conversation Projection State Consolidation"
status: planned
jira: ""
owner: ""
created: 2026-04-06
updated: 2026-04-06
---

# 020 — Conversation Projection State Consolidation

Consolidate assistant-step assembly and projector state so live signal reduction and persisted-entry reconstruction share one canonical step-projection rule, and `ConversationProjector` caches richer read-model state instead of only storing rendered message lists in ETS.