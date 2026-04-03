---
id: "010"
title: "LLM Observability & Tracing"
status: in-progress
jira: ""
owner: ""
created: 2026-03-31
updated: 2026-04-03
---

# 010 — LLM Observability & Tracing

Add developer-facing observability for LLM agent interactions using a Murmur-owned tracing implementation that renders cleanly in Arize Phoenix. Developers must be able to inspect exact model inputs and outputs, structured input conversations and assistant output messages, token usage, tool calls, nested execution trees, and cross-agent causation without losing Murmur's react-loop, steering-message, and team semantics.

After updating to the latest `jido_ai`, ticket 010 can use the new request, LLM, and tool lifecycle telemetry surfaced by the ReAct runtime instead of patching the dependency locally.

The ticket's attribute-level export contract is defined in [data-contract.md](data-contract.md).
