---
id: "013"
title: "Agent-Centric Phoenix Sessions"
status: specifying
jira: ""
owner: ""
created: 2026-04-04
updated: 2026-04-04
---

# 013 — Agent-Centric Phoenix Sessions

Redefine Murmur's Phoenix session grouping model so Phoenix Sessions shows one row per agent session rather than one row per inferred discussion. This ticket covers removing the current direct-chat discussion cache and inactivity timeout heuristic from session grouping, exporting agent identity as the Phoenix `session.id`, and preserving cross-turn and cross-agent workflow correlation through explicit Murmur metadata rather than the Phoenix Sessions grouping key.