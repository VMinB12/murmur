# Implementation Plan: Artifact System Extraction

**Branch**: `003-artifact-extraction` | **Date**: 2026-03-29 | **Spec**: [spec.md](specs/003-artifact-extraction/spec.md)  
**Input**: Feature specification from `/specs/003-artifact-extraction/spec.md`

## Summary

Extract the artifact system (`Artifact`, `ArtifactPlugin`, `StoreArtifact`) from `jido_murmur` into a standalone `jido_artifacts` package. Enhance the API with function-based merge callbacks, metadata envelopes (version, timestamp, source tracking), and CloudEvents `source`/`subject` fields. Domain tool packages (e.g., `jido_arxiv`) depend on `jido_artifacts` instead of `jido_murmur`, eliminating the heavyweight transitive dependency.

## Technical Context

**Language/Version**: Elixir >= 1.15 on OTP  
**Primary Dependencies**: jido ~> 2.0, jido_signal ~> 2.0, jido_action ~> 2.0, phoenix_pubsub ~> 2.0, jason ~> 1.0  
**Storage**: In-memory agent state (ETS), persisted via Jido checkpoint system. No Ecto/PostgreSQL dependency.  
**Testing**: ExUnit — unit tests for Merge helpers, StoreArtifact action, Artifact.emit API, ArtifactPlugin signal handling  
**Target Platform**: Elixir library (Hex package)  
**Project Type**: Library (extracted from umbrella app into standalone package)  
**Performance Goals**: Merge callbacks must be pure functions with no DB queries. StoreArtifact runs synchronously in agent process.  
**Constraints**: Max 5 direct dependencies. No jido_murmur dependency. Backward-compatible envelope unwrapping.  
**Scale/Scope**: 3 existing modules to extract + 1 new module (Merge helpers). ~500 LOC total.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Code Quality — Single responsibility | ✅ PASS | Each extracted module has one job |
| I. Code Quality — No needless backward compat | ✅ PASS | No packages published; clean break acceptable |
| I. Code Quality — YAGNI | ✅ PASS | `:scope` option is minimal (one keyword), justified by spec |
| II. Testing Standards | ✅ PASS | Unit tests for all public API surfaces planned |
| III. UX Consistency — Renderers unchanged | ✅ PASS | Envelope unwrap in ArtifactPanel keeps renderers working |
| IV. Performance — No N+1 | ✅ PASS | No DB queries in artifact path |
| V. DX — Dependencies | ✅ PASS | 5 deps total, all already in tree |
| Technology Constraints — Req | N/A | No HTTP in artifact system |

**Post-Phase 1 Re-check**: All gates still pass. Data model adds no new complexity. Merge is a pure function, envelope is a plain map.

## Project Structure

### Documentation (this feature)

```text
specs/003-artifact-extraction/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── jido-artifacts-api.md
└── tasks.md             # Phase 2 output (NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
apps/
├── jido_artifacts/                    # NEW — extracted package
│   ├── mix.exs
│   ├── lib/
│   │   ├── jido_artifacts.ex          # Config accessors (pubsub/0)
│   │   ├── jido_artifacts/
│   │   │   ├── artifact.ex            # emit/4, artifact_topic/1
│   │   │   ├── artifact_plugin.ex     # Jido.Plugin
│   │   │   ├── merge.ex               # Built-in merge helpers
│   │   │   └── actions/
│   │   │       └── store_artifact.ex  # Jido.Action
│   │   └── mix/
│   │       └── tasks/
│   │           └── jido_artifacts.install.ex
│   └── test/
│       ├── test_helper.exs
│       ├── jido_artifacts/
│       │   ├── artifact_test.exs
│       │   ├── merge_test.exs
│       │   ├── artifact_plugin_test.exs
│       │   └── actions/
│       │       └── store_artifact_test.exs
│
├── jido_murmur/                       # MODIFIED — remove artifact modules
│   └── lib/jido_murmur/
│       ├── artifact.ex                # DELETE (moved to jido_artifacts)
│       ├── artifact_plugin.ex         # DELETE (moved to jido_artifacts)
│       └── actions/store_artifact.ex  # DELETE (moved to jido_artifacts)
│
├── jido_murmur_web/                   # MODIFIED — update ArtifactPanel
│   └── lib/jido_murmur_web/components/
│       └── artifact_panel.ex          # Add envelope unwrapping
│
├── jido_arxiv/                        # MODIFIED — dep change
│   └── mix.exs                        # jido_murmur → jido_artifacts
│
└── murmur_demo/                       # MODIFIED — add jido_artifacts dep + config
    └── config/config.exs              # Add :jido_artifacts config
```

**Structure Decision**: New umbrella app `jido_artifacts` under `apps/`. Follows existing umbrella convention alongside jido_murmur, jido_tasks, etc.
