# Implementation Plan: Data Contract Enforcement

**Branch**: `009-data-contract-enforcement` | **Date**: 2026-04-02 | **Spec**: [Spec.md](Spec.md)
**Input**: Feature specification from `/specs/tickets/009-data-contract-enforcement/Spec.md`

## Summary

Harden Murmur's inter-module data boundaries by making `%JidoArtifacts.Envelope{}` the only in-memory artifact shape, converting `JidoSql.QueryExecutor.execute/3` to return `%JidoSql.QueryResult{}`, removing legacy renderer fallbacks, and adding enough `@spec` coverage for manual Dialyzer to validate the new contracts. The rollout is a hard cutover: checkpoints created before ticket 009 are intentionally discarded, and no compatibility loader or fallback path remains in the codebase.

## Technical Context

**Language/Version**: Elixir >= 1.15 on OTP with Phoenix 1.8 / LiveView 1.1
**Primary Dependencies**: `jido`, `jido_artifacts`, `jido_murmur`, `jido_sql`, `ecto_sql`, `phoenix_live_view`, `dialyxir`
**Storage**: Agent checkpoints persisted by `JidoMurmur.Storage.Ecto` using `:erlang.term_to_binary` inside the JSONB wrapper; artifact state stored in `agent.state.artifacts`
**Testing**: ExUnit, Phoenix.LiveViewTest, component rendering tests, targeted checkpoint round-trip tests, manual `mix dialyzer`
**Target Platform**: Umbrella project spanning library apps and the Phoenix demo app
**Constraints**: No backward compatibility for pre-009 checkpoints, no legacy `unwrap_envelope` paths, no Dialyzer step added to `mix precommit`
**Scale/Scope**: Contract changes across `jido_artifacts`, `jido_sql`, `jido_murmur`, `jido_murmur_web`, `jido_tasks`, and `murmur_demo`

## Architecture Alignment

This ticket does not introduce a new subsystem or architectural direction. It hardens the existing artifact, SQL, and signal boundaries so the runtime behavior matches the project architecture already described in `specs/Architecture/README.md` and `specs/Architecture/jido-artifacts.md`.

## Implementation Phases

## Phase 1: Canonical Artifact Envelope

Introduce `JidoArtifacts.Envelope` as the single canonical artifact contract. `StoreArtifact` remains the authoritative persistence action, but `ArtifactPlugin` and the LiveView artifact handler must now move the exact same `%Envelope{}` shape across the live path and the persisted path. `Artifact.emit/4` will merge against the envelope payload rather than the envelope struct, so merge helpers continue to operate on domain data while the inter-module boundary stays typed.

## Phase 2: Renderer and Checkpoint Normalization

Update the Phoenix-side artifact consumers so they pattern-match on `%Envelope{}` at the boundary and pass only `envelope.data` to renderer implementations. This removes `unwrap_envelope` compatibility helpers from both `murmur_demo` and `jido_murmur_web`. Checkpoint behavior stays on `:erlang.term_to_binary`; the change here is to ensure the stored term is already `%Envelope{}` and survives thaw without conversion code.

## Phase 3: Artifact Pipeline Integration Tests

Promote the current artifact tests from shape-specific unit checks to contract-focused integration coverage. The test suite should verify both signal-driven live updates and thawed checkpoints with `%Envelope{}` data, asserting badge counts, labels, and rendered content for the concrete artifact types Murmur already ships with.

## Phase 4: Typed SQL Result Boundary

Add `%JidoSql.QueryResult{}` for the `QueryExecutor.execute/3` return value and migrate its consumers to pattern-match on that struct. This change is intentionally limited to the public query execution boundary; helper return shapes can stay internal unless the implementation proves a second typed struct is needed to keep the boundary coherent.

## Phase 5: Public Specs and Manual Dialyzer

Once the artifact and SQL contracts are stable, add `@spec` coverage to the public functions called across app boundaries: `JidoArtifacts.Artifact`, `JidoArtifacts.Envelope`, `JidoSql.QueryExecutor`, `JidoMurmur.Runner`, `JidoMurmur.UITurn`, `JidoTasks.Tasks`, and `JidoMurmur.Storage.Ecto`. `mix precommit` remains unchanged. Dialyzer is a manual gate run after compilation and tests are green, with `.dialyzer_ignore.exs` added only if a warning is proven to be a false positive.

## Phase 6: Signal Schema Tightening

Replace `:any` fields in the Murmur-owned signal families with concrete types that reflect the actual contracts in use. For `murmur.message.*` and `task.*`, this means switching to precise field types in the existing signal modules. For `artifact.*`, the application-level plan is to introduce a typed signal schema or equivalent typed wrapper so the artifact signal family documents `%Envelope{}` rather than relying on untyped payloads, without requiring a Jido framework change.

## Key Design Decisions

- `%JidoArtifacts.Envelope{}` is the only allowed artifact shape at inter-module boundaries.
- Old checkpoints are not migrated or adapted. The rollout assumes the database will be cleared.
- `:erlang.term_to_binary` remains the checkpoint encoding because it already preserves Elixir structs losslessly.
- Dialyzer stays manual so type hardening improves safety without slowing the default local commit path.
- Signal typing is handled inside Murmur apps, not by extending Jido as part of this ticket.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Merge logic accidentally operates on `%Envelope{}` instead of payload data | Artifact append/merge behavior breaks silently | Update `Artifact.emit/4` first and add unit tests for merge behavior with existing envelopes |
| LiveView still stores raw artifact data in one path | Renderers keep requiring fallback clauses | Convert the LiveView artifact signal handler and `sql_results` re-execution path in the same implementation slice |
| Renderer assumptions about raw maps or lists cause UI regressions | Artifact badges or detail panes render wrong counts/content | Add component tests and live artifact integration tests before broad refactors |
| Dialyzer surfaces noisy warnings after specs are added | Manual verification becomes slow or inconclusive | Add specs after boundary refactors settle, then triage warnings in one pass and create `.dialyzer_ignore.exs` only if justified |

## Validation Strategy

1. Run focused unit tests for `jido_artifacts` and `jido_sql` as each contract changes.
2. Run artifact component and LiveView tests covering both live updates and checkpoint round-trips.
3. Run `mix test` from the repo root once the P1 and P2 work is complete.
4. Run `mix dialyzer` manually after `@spec` coverage is in place.
5. Run `mix precommit` at the end to confirm the normal local quality gate still passes without Dialyzer in the alias.