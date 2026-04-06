---
id: "017"
title: "Canonical Conversation Step Ordering"
status: done
jira: ""
owner: ""
created: 2026-04-06
updated: 2026-04-06
---

# 017 — Canonical Conversation Step Ordering

Define and validate a core-owned ordering rule for top-level conversation messages so Murmur renders human messages and assistant steps by when they first came into existence rather than by `request_id`, display id shape, or LiveView-local insertion heuristics.

Implemented on 2026-04-06. This ticket absorbed the required `UITurn` retirement work for the canonical read path because request-level collapsing and the legacy persisted projection boundary prevented Murmur from expressing assistant-step ordering cleanly.

The shipped result defines first-seen ordering over top-level messages, segments assistant output by assistant step, removes `UITurn` from the canonical read path, and eliminates the busy-follow-up insertion heuristic from `WorkspaceLive`. Direct human sends remain optimistic at the LiveView edge; the canonical core-owned boundary now covers assistant-step projection and visible programmatic ingress ordering.