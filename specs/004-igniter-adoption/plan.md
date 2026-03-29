# Implementation Plan: Igniter Adoption

**Branch**: `004-igniter-adoption` | **Date**: 2026-03-29 | **Spec**: [spec.md](specs/004-igniter-adoption/spec.md)  
**Input**: Feature specification from `/specs/004-igniter-adoption/spec.md`

## Summary

Adopt Igniter as an optional dependency across all Murmur ecosystem packages. Convert existing plain Mix.Task install commands to Igniter-powered tasks with AST-aware code modification, diff previews, idempotency, and dependency chaining. Add a profile scaffolding generator. The guard pattern (`Code.ensure_loaded?(Igniter)`) ensures packages compile and work without Igniter.

## Technical Context

**Language/Version**: Elixir >= 1.15 on OTP  
**Primary Dependencies**: igniter ~> 0.7 (optional, runtime: false), sourceror (transitive via igniter)  
**Storage**: N/A — install tasks modify source files, not databases  
**Testing**: ExUnit — test idempotency, guard pattern compilation, generated output correctness  
**Target Platform**: Mix tasks (developer tooling)  
**Project Type**: Developer tooling (Mix tasks for library packages)  
**Performance Goals**: Install tasks complete in < 5s for a fresh project  
**Constraints**: Igniter must be optional — packages must compile when Igniter is absent  
**Scale/Scope**: 4 packages with install tasks (jido_murmur, jido_tasks, jido_murmur_web, jido_artifacts) + 1 generator (profile)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Code Quality — Single responsibility | ✅ PASS | Each install task handles one package's setup |
| I. Code Quality — YAGNI | ✅ PASS | Only tasks needed for current packages, no speculative generators |
| II. Testing Standards | ✅ PASS | Install tasks tested against fresh Phoenix scaffold |
| V. DX — Single command setup | ✅ PASS | `mix jido_murmur.install` delivers full setup |
| V. DX — Generator outputs | ✅ PASS | Profile generator follows Phoenix generator conventions |
| Technology — New deps justified | ✅ PASS | Igniter is optional, already used by Jido core |

**Post-Phase 1 Re-check**: All gates pass. Guard pattern ensures zero compilation risk. Chaining design is simple (one prerequisite check).

## Project Structure

### Documentation (this feature)

```text
specs/004-igniter-adoption/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── install-tasks.md
└── tasks.md             # Phase 2 output (NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
apps/
├── jido_murmur/
│   ├── mix.exs                                    # MODIFIED — add igniter optional dep
│   └── lib/mix/tasks/
│       └── jido_murmur.install.ex                 # REWRITE — Igniter + guard pattern
│       └── jido_murmur.gen.profile.ex             # NEW — profile scaffolding generator
│
├── jido_tasks/
│   ├── mix.exs                                    # MODIFIED — add igniter optional dep
│   └── lib/mix/tasks/
│       └── jido_tasks.install.ex                  # REWRITE — Igniter + chaining + guard
│
├── jido_murmur_web/
│   ├── mix.exs                                    # MODIFIED — add igniter optional dep
│   └── lib/mix/tasks/
│       └── jido_murmur_web.install.ex             # REWRITE — Igniter + guard pattern
│
└── jido_artifacts/
    ├── mix.exs                                    # MODIFIED — add igniter optional dep
    └── lib/mix/tasks/
        └── jido_artifacts.install.ex              # NEW — Igniter + guard pattern
```

**Structure Decision**: Modify existing install task files in each package. No new directories needed. Generator lives alongside install task.
