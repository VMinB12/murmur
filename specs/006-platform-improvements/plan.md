# Implementation Plan: Platform Infrastructure Improvements

**Branch**: `006-platform-improvements` | **Date**: 2026-03-29 | **Spec**: [spec.md](specs/006-platform-improvements/spec.md)  
**Input**: Feature specification from `/specs/006-platform-improvements/spec.md`

## Summary

Platform-level improvements: centralize PubSub topic construction in a `JidoMurmur.Topics` helper module with workspace context in all topics; thread `workspace_id` through plugins; add startup config validation for required keys; add `:telemetry` events to jido_tasks; define `JidoMurmur.AgentProfile` behaviour for compile-time profile validation.

## Technical Context

**Language/Version**: Elixir >= 1.15 on OTP  
**Primary Dependencies**: phoenix_pubsub ~> 2.0, telemetry ~> 1.0 (already in tree), ecto_sql (for jido_tasks context)  
**Storage**: PostgreSQL via Ecto SQL (jido_tasks context module)  
**Testing**: ExUnit — topic helper unit tests, config validation tests, telemetry event capture, behaviour compile warnings  
**Target Platform**: Elixir umbrella (web service)  
**Project Type**: Web service (infrastructure refactor)  
**Performance Goals**: Topic helpers are pure string functions — zero allocation overhead. Telemetry adds < 1μs per operation.  
**Constraints**: Topic migration must be atomic (all publishers and subscribers update together). Config validation must not run in test env unless config is present.  
**Scale/Scope**: ~20 PubSub topic references to update, 3 context functions to instrument, 1 behaviour to define, 2+ profile modules to annotate

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Code Quality — Single responsibility | ✅ PASS | Topics module has one job. Config module has one job. |
| I. Code Quality — No unnecessary abstraction | ✅ PASS | Topics module is a thin function layer, not a complex abstraction |
| II. Testing Standards | ✅ PASS | All new modules get unit tests |
| III. UX Consistency | N/A | No UI changes |
| IV. Performance — Dev reload fast | ✅ PASS | No compile-time macros or heavy code gen |
| V. DX — Error messages | ✅ PASS | Config validation produces actionable messages |
| V. DX — mix setup | ✅ PASS | Config validation error points to install task |
| Technology — Telemetry | ✅ PASS | `:telemetry` already a dependency |

**Post-Phase 1 Re-check**: All gates pass. Topics module adds minimal indirection (just function calls). Config validation is a single check at startup. Telemetry follows established convention.

## Project Structure

### Documentation (this feature)

```text
specs/006-platform-improvements/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── platform-contracts.md
└── tasks.md             # Phase 2 output (NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
apps/
├── jido_murmur/
│   ├── lib/jido_murmur/
│   │   ├── topics.ex                       # NEW — centralized PubSub topic helpers
│   │   ├── config.ex                       # NEW — startup config validation
│   │   ├── agent_profile.ex                # NEW — @behaviour definition
│   │   ├── supervisor.ex                   # MODIFIED — call Config.validate!/0
│   │   ├── agent_helper.ex                 # MODIFIED — use Topics module
│   │   ├── streaming_plugin.ex             # MODIFIED — use Topics module, access workspace_id
│   │   ├── artifact_plugin.ex              # MODIFIED — use Topics module, access workspace_id
│   │   ├── runner.ex                       # MODIFIED — use Topics module, thread workspace_id
│   │   └── tell_action.ex                  # MODIFIED — use Topics module
│   └── test/jido_murmur/
│       ├── topics_test.exs                 # NEW
│       ├── config_test.exs                 # NEW
│       └── agent_profile_test.exs          # NEW
│
├── jido_tasks/
│   ├── lib/jido_tasks/
│   │   ├── config.ex                       # NEW — startup config validation
│   │   ├── tasks.ex                        # MODIFIED — add telemetry spans
│   │   └── tools/
│   │       ├── add_task.ex                 # MODIFIED — use Topics module
│   │       └── update_task.ex              # MODIFIED — use Topics module
│   └── test/jido_tasks/
│       ├── config_test.exs                 # NEW
│       └── tasks_telemetry_test.exs        # NEW
│
└── murmur_demo/
    └── lib/murmur/agents/profiles/
        ├── general_agent.ex                # MODIFIED — add @behaviour
        └── arxiv_agent.ex                  # MODIFIED — add @behaviour
```

**Structure Decision**: New modules in existing package directories. No structural changes to the umbrella.
