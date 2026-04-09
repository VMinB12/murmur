# 2026-04-04

- Completed ticket 012, replacing Murmur's older busy-agent follow-up path with a per-session ingress coordinator built on native `jido_ai` `steer/3` and `inject/3` controls.

# Changelog

All notable changes to this project are documented here. Entries are in reverse chronological order.

## [Unreleased]

### Added

- Migrated to spec-driven methodology (from speckit)
- SQL agent plugin (`jido_sql`) for natural-language-to-SQL queries
- Architecture documentation for all 7 umbrella packages
- Ecosystem composition guide
- `%JidoArtifacts.Envelope{}`, `%JidoSql.QueryResult{}`, and typed artifact signal payload structs to harden cross-package data contracts

### Changed

- Completed tickets 024 through 027: conversation snapshots now load through a dedicated live-or-storage source boundary, the canonical read model carries explicit source and persistence freshness metadata, shared session map contracts are centralized under `JidoMurmur.SessionContract`, and the dead raw `ai.*` chat PubSub path has been removed in favor of Murmur-owned canonical conversation updates only.
- Completed ticket 023 tell intent contract: `tell` now requires an advisory `intent` enum, inter-agent messages use a reusable hidden HTML-comment envelope, tell-generated messages render through markdown while direct human messages remain raw text, and the final validation pass now includes a clean `mix dialyzer` run on this change set.
- Completed tickets 019 through 022: visible direct ingress is now core-owned, the conversation projector caches the full canonical read model without the legacy message-list snapshot path, agent lifecycle orchestration moved behind `AgentHelper`, and Murmur now documents its data model and data contracts explicitly in `specs/Architecture/`.
- Completed ticket 017 canonical conversation step ordering: top-level chat messages now sort by Murmur-owned first-seen metadata, one outer request can project to multiple assistant-step messages, the legacy `UITurn` read path was removed, and busy follow-up ordering no longer relies on LiveView insertion heuristics.
- Completed ticket 016 conversation read model and streaming consistency: `jido_murmur` now owns canonical conversation snapshots and incremental updates, `murmur_demo` renders projector-backed conversation state instead of raw `ai.*` stream state, and the redundant `ChatStream` surface was removed from `jido_murmur_web`.
- Completed ticket 013 agent-centric Phoenix sessions: `session.id` now exports the executing agent session, each react loop remains its own trace, `interaction_id` and discussion rollover were removed from the canonical model, and only immediate parent-trace causation is preserved.
- Completed ticket 015 actor identity and display projection cleanup: runtime context now distinguishes current and origin actors explicitly, `UITurn` emits canonical display messages, shared/demo chat rendering is actor-aware instead of string-heuristic-driven, and presentation wording now stays at the UI edge.
- Completed ticket 014 runtime metadata boundary cleanup: canonical ingress metadata now projects through a typed runtime boundary, tell hop depth is configurable and non-crashing at the limit, and visible programmatic delivery is shared across tell and task-assignment paths.
- Completed ticket 009 data contract hardening: live and persisted artifact paths now share the `%JidoArtifacts.Envelope{}` boundary, SQL execution now returns `%JidoSql.QueryResult{}`, legacy envelope unwrap fallbacks were removed, and signal schemas now document typed `artifact.*`, `murmur.message.*`, and `task.*` payloads.
- Completed ticket 011 frontend boundary refactor: `jido_murmur_web` now ships a domain-agnostic workspace shell, `murmur_demo` owns SQL/arXiv artifact integrations, the workspace presentation is split into focused modules, and the demo child app now builds assets through its own configured aliases
- Replaced AgentObs-era tracing with Murmur-owned turn, LLM, and tool observability that renders ordered LLM input/output conversations correctly in Arize Phoenix
- Moved existing tickets 001-008 to `specs/tickets/` and marked as done
- Moved `docs/` research files into their respective ticket folders

### Fixed

### Removed

- Removed speckit framework (`.specify/`, `.github/agents/`, prompt files)
- Removed `docs/` folder (contents redistributed to ticket folders)
