---
id: "024"
title: "Conversation Snapshot Freshness Contract"
status: done
jira: ""
owner: ""
created: 2026-04-08
updated: 2026-04-09
---

# 024 — Conversation Snapshot Freshness Contract

Formalize the canonical freshness and source-of-truth rules for Murmur conversation snapshots so the projector cache cannot silently diverge from runtime or persisted history. This ticket now tracks the stronger approach: keep one canonical `ConversationReadModel`, keep the ETS cache as its canonical materialized in-memory form, and make source provenance plus revision semantics explicit so snapshot serving and reconciliation stop relying on heuristic freshness recovery. The projector source-boundary cleanup and the dead `ai.*` chat-path removal are now tracked separately in tickets `026` and `027`.