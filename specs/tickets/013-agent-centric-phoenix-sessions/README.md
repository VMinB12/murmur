---
id: "013"
title: "Agent-Centric Phoenix Sessions"
status: planned
jira: ""
owner: ""
created: 2026-04-04
updated: 2026-04-05
---

# 013 — Agent-Centric Phoenix Sessions

Redefine Murmur's Phoenix session grouping model so Phoenix Sessions shows one row per agent session and each executed react loop remains its own trace. This ticket removes discussion and `interaction_id` from the canonical observability model, deletes the inactivity-based session rollover heuristic, and preserves only immediate cross-agent handoff causation through parent-trace metadata.