---
id: "027"
title: "Remove Raw AI Stream Chat Path"
status: done
jira: ""
owner: ""
created: 2026-04-09
updated: 2026-04-09
---

# 027 — Remove Raw AI Stream Chat Path

Remove the unused raw `ai.*` PubSub chat path from the demo chat surface and clean up the extra stream-topic fanout if no remaining runtime consumer still depends on it. This ticket is intentionally small and focused: Murmur should continue to reduce raw lifecycle facts internally, but the product chat contract should expose only Murmur-owned canonical conversation updates.