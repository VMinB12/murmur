---
id: "015"
title: "Actor Identity And Display Projection Cleanup"
status: done
jira: ""
owner: ""
created: 2026-04-05
updated: 2026-04-05
---

# 015 — Actor Identity And Display Projection Cleanup

Completed the actor identity and display projection cleanup introduced after ticket 014 so Murmur now uses explicit actor semantics across runtime and UI boundaries, projects canonical display messages instead of relying on sender-name heuristics, keeps presentation wording at the rendering edge, and documents plus tests the resulting boundary end to end.