---
id: "016"
title: "Conversation Read Model And Streaming Consistency"
status: done
jira: ""
owner: ""
created: 2026-04-05
updated: 2026-04-06
---

# 016 — Conversation Read Model And Streaming Consistency

Define a cleanup that replaces the split between raw live-stream rendering and persisted conversation refresh with one core-owned conversation projector, one Murmur-owned UI update contract, and stable turn identity across in-progress and finalized turns so tool-call visibility no longer depends on PubSub timing between separate topics.

Implemented on 2026-04-06, including the canonical projector boundary, reconnect-safe snapshots, stable assistant-turn identity, and retirement of the redundant `ChatStream` UI surface.