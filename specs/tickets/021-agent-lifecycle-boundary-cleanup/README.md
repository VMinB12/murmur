---
id: "021"
title: "Agent Lifecycle Boundary Cleanup"
status: planned
jira: ""
owner: ""
created: 2026-04-06
updated: 2026-04-06
---

# 021 — Agent Lifecycle Boundary Cleanup

Move duplicated agent start, thaw, and storage-cleanup policy out of `murmur_demo` and behind a smaller core-owned lifecycle API so the reference LiveView orchestrates sessions without re-implementing Murmur's runtime lifecycle rules.