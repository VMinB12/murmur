# Changelog

All notable changes to this project are documented here. Entries are in reverse chronological order.

## [Unreleased]

### Added

- Migrated to spec-driven methodology (from speckit)
- SQL agent plugin (`jido_sql`) for natural-language-to-SQL queries
- Architecture documentation for all 7 umbrella packages
- Ecosystem composition guide
- Ticket 009 (Data Contract Enforcement) on roadmap

### Changed

- Completed ticket 011 frontend boundary refactor: `jido_murmur_web` now ships a domain-agnostic workspace shell, `murmur_demo` owns SQL/arXiv artifact integrations, the workspace presentation is split into focused modules, and the demo child app now builds assets through its own configured aliases
- Replaced AgentObs-era tracing with Murmur-owned turn, LLM, and tool observability that renders ordered LLM input/output conversations correctly in Arize Phoenix
- Grouped direct-chat traces into discussion-scoped Phoenix sessions with inactivity rollover while preserving explicit cross-agent interaction propagation
- Moved existing tickets 001-008 to `specs/tickets/` and marked as done
- Moved `docs/` research files into their respective ticket folders

### Fixed

### Removed

- Removed speckit framework (`.specify/`, `.github/agents/`, prompt files)
- Removed `docs/` folder (contents redistributed to ticket folders)
