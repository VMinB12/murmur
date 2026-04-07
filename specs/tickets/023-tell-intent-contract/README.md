---
id: "023"
title: "Tell Intent Contract"
status: done
jira: ""
owner: ""
created: 2026-04-07
updated: 2026-04-07
---

# 023 — Tell Intent Contract

Define a first-class semantic contract for `tell` so one agent can express whether a message is a notification, a response-seeking request, a delegation, a handoff, or another coordination message without overloading Murmur's delivery mechanics. This ticket now has a completed async, non-enforcing runtime slice with a required `intent` enum, LLM-facing tool-description wording, a reusable hidden HTML comment envelope helper for trusted programmatic markdown messages, tell-only markdown rendering in chat surfaces, updated docs, and passing validation via `mix precommit` and `mix dialyzer`.

Completed on 2026-04-07.