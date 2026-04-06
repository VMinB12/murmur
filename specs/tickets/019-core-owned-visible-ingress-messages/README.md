---
id: "019"
title: "Core-Owned Visible Ingress Messages"
status: planned
jira: ""
owner: ""
created: 2026-04-06
updated: 2026-04-06
---

# 019 — Core-Owned Visible Ingress Messages

Move canonical visible human ingress out of `WorkspaceLive` and into `jido_murmur` so direct human messages and visible programmatic messages share one Murmur-owned contract, with any optimistic UI behavior reduced to transient presentation state rather than canonical message creation.