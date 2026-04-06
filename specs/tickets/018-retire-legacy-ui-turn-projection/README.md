---
id: "018"
title: "Retire Legacy UITurn Projection"
status: archived
jira: ""
owner: ""
created: 2026-04-06
updated: 2026-04-06
---

# 018 — Retire Legacy UITurn Projection

Archived on 2026-04-06. This ticket was superseded by ticket 017 after implementation work showed that canonical first-seen ordering must be defined over assistant steps rather than whole requests.

Achieving that cleanly requires removing request-level `UITurn` grouping and moving persisted-entry projection into the canonical conversation read model in the same implementation pass as the assistant-step ordering rewrite. Keeping `UITurn` retirement as a separate ticket would force a transitional adapter or staged compatibility layer, which this project explicitly rejects.