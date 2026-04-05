---
id: "016"
title: "Conversation Read Model And Streaming Consistency"
status: planned
jira: ""
owner: ""
created: 2026-04-05
updated: 2026-04-05
---

# 016 — Conversation Read Model And Streaming Consistency

Investigate and define a cleanup that removes the split between the ad hoc live streaming UI path and the persisted conversation refresh path, so in-progress agent turns and refreshed history are rendered from one consistent read model and tool-call visibility no longer depends on PubSub timing between separate topics.