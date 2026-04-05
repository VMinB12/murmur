---
id: "013"
title: "Agent-Centric Phoenix Sessions"
status: done
jira: ""
owner: ""
created: 2026-04-04
updated: 2026-04-05
---

# 013 — Agent-Centric Phoenix Sessions

Completed on 2026-04-05 after redefining Murmur's Phoenix session grouping model so Phoenix Sessions now shows one row per agent session while each executed react loop remains its own trace. This ticket removed discussion and `interaction_id` from the canonical observability model, deleted the inactivity-based session rollover heuristic, preserved only immediate cross-agent handoff causation through parent-trace metadata, and validated the new contract with targeted suites plus `mix precommit`.