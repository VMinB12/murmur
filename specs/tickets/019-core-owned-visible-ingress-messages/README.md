---
id: "019"
title: "Core-Owned Visible Ingress Messages"
status: done
jira: ""
owner: ""
created: 2026-04-06
updated: 2026-04-07
---

# 019 — Core-Owned Visible Ingress Messages

Move canonical visible human ingress out of `WorkspaceLive` and into `jido_murmur` so direct human messages and visible programmatic messages share one Murmur-owned contract, with any optimistic UI behavior reduced to transient presentation state rather than canonical message creation.

Implemented on 2026-04-07. Direct human sends and visible programmatic sends now share the same Murmur-owned visible ingress contract, stable visible message identity is attached in core, and the demo UI only overlays transient pending state while waiting for canonical ingress echo.