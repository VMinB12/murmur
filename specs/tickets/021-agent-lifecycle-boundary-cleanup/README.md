---
id: "021"
title: "Agent Lifecycle Boundary Cleanup"
status: done
jira: ""
owner: ""
created: 2026-04-06
updated: 2026-04-07
---

# 021 — Agent Lifecycle Boundary Cleanup

Move duplicated agent start, thaw, and storage-cleanup policy out of `murmur_demo` and behind a smaller core-owned lifecycle API so the reference LiveView orchestrates sessions without re-implementing Murmur's runtime lifecycle rules.

Implemented on 2026-04-07. The demo LiveView now delegates session subscription, fresh-start handling, stop, and storage cleanup through `JidoMurmur.AgentHelper` rather than encoding those lifecycle rules locally.