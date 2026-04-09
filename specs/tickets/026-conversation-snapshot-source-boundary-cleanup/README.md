---
id: "026"
title: "Conversation Snapshot Source Boundary Cleanup"
status: done
jira: ""
owner: ""
created: 2026-04-09
updated: 2026-04-09
---

# 026 — Conversation Snapshot Source Boundary Cleanup

Extract snapshot-source discovery and offline history loading out of `ConversationProjector` so the projector reduces canonical inputs instead of performing ad hoc runtime lookup, thaw-driven recovery, and source selection itself. This ticket is intentionally smaller than ticket `024`: it preserves the current one-model architecture while cleaning up a leaky implementation boundary that makes the projector harder to reason about and test.