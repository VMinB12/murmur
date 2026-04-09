---
id: "025"
title: "Shared Session Contract Type"
status: done
jira: ""
owner: ""
created: 2026-04-08
updated: 2026-04-09
---

# 025 — Shared Session Contract Type

Create a shared Murmur-owned session contract type so `session_like` is not redefined piecemeal across ingress, runner, projector, and other modules. This follow-up ticket exists because the current codebase duplicates overlapping session-map type definitions in multiple places, which increases drift risk, creates repeated dialyzer cleanup, and weakens the boundary between stable session identity requirements and module-specific optional fields.