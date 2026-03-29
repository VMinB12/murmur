# Implementation Plan: CloudEvents Signal Alignment

**Branch**: `005-cloudevents-alignment` | **Date**: 2026-03-29 | **Spec**: [spec.md](specs/005-cloudevents-alignment/spec.md)  
**Input**: Feature specification from `/specs/005-cloudevents-alignment/spec.md`

## Summary

Align all PubSub messages with the CloudEvents standard by replacing ad-hoc tuple formats with proper `%Jido.Signal{}` envelopes. Populate `subject` fields for entity-scoped filtering. Define typed signal modules for compile-time schema validation. Replace `Signal.ID.generate!()` with `Uniq.UUID.uuid7()` at non-signal call sites. Create a signal catalog document.

## Technical Context

**Language/Version**: Elixir >= 1.15 on OTP  
**Primary Dependencies**: jido_signal ~> 2.0 (provides `use Jido.Signal`), uniq (UUID7, transitive), phoenix_pubsub ~> 2.0  
**Storage**: N/A — signals are ephemeral PubSub messages  
**Testing**: ExUnit — verify signal structs, handler pattern matching, typed module validation  
**Target Platform**: Elixir umbrella (web service)  
**Project Type**: Web service (cross-cutting refactor across umbrella apps)  
**Performance Goals**: Zero measurable overhead vs current tuple broadcasts  
**Constraints**: All handlers must migrate atomically (single PR) to avoid silent message drops  
**Scale/Scope**: 5 tuple patterns to migrate, 5 typed signal modules to create, ~15 handler functions to update

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Code Quality — Pattern matching preferred | ✅ PASS | Signal struct matching is more explicit than tuple matching |
| I. Code Quality — No needless backward compat | ✅ PASS | Atomic migration, no dual-format period needed |
| II. Testing Standards — Deterministic tests | ✅ PASS | Signal struct assertions are deterministic |
| III. UX Consistency | N/A | No UI changes |
| IV. Performance | ✅ PASS | Signal struct creation has negligible overhead vs tuple creation |
| V. DX — Documentation | ✅ PASS | Signal catalog serves as developer reference |

**Post-Phase 1 Re-check**: All gates pass. Typed modules add compile-time value without runtime cost. Handler migration is well-scoped.

## Project Structure

### Documentation (this feature)

```text
specs/005-cloudevents-alignment/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── signal-envelope.md
└── tasks.md             # Phase 2 output (NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
apps/
├── jido_murmur/
│   ├── lib/jido_murmur/
│   │   ├── signals/                           # NEW — typed signal modules
│   │   │   ├── message_completed.ex
│   │   │   └── message_received.ex
│   │   ├── streaming_plugin.ex                # MODIFIED — broadcast Signal directly (no tuple wrapper)
│   │   ├── artifact_plugin.ex                 # MODIFIED — broadcast Signal (moves to jido_artifacts with 003)
│   │   ├── runner.ex                          # MODIFIED — broadcast Signal instead of tuples
│   │   └── tell_action.ex                     # MODIFIED — Signal broadcast + UUID migration
│   └── test/jido_murmur/
│       └── signals/                           # NEW — typed signal tests
│
├── jido_tasks/
│   ├── lib/jido_tasks/
│   │   ├── signals/                           # NEW — typed signal modules
│   │   │   ├── task_created.ex
│   │   │   └── task_updated.ex
│   │   └── tools/
│   │       ├── add_task.ex                    # MODIFIED — Signal broadcast + UUID migration
│   │       └── update_task.ex                 # MODIFIED — Signal broadcast + UUID migration
│   └── test/jido_tasks/
│       └── signals/                           # NEW — typed signal tests
│
├── jido_artifacts/                            # (from 003) — already uses Signal
│   └── lib/jido_artifacts/
│       └── signals/
│           └── artifact_emitted.ex            # NEW — typed signal module
│
└── murmur_demo/
    └── lib/murmur_web/live/
        └── workspace_live.ex                  # MODIFIED — update all handle_info handlers

docs/
└── signal-catalog.md                          # NEW — complete signal type reference
```

**Structure Decision**: `signals/` subdirectories in each package following the same pattern as `tools/` and `actions/`.
