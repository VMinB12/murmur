# Implementation Plan: LLM OpenTelemetry Tracing

**Branch**: `007-llm-otel-tracing` | **Date**: 2026-03-30 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/007-llm-otel-tracing/spec.md`

## Summary

Every LLM call made by Jido agents must produce rich OpenTelemetry traces with full input/output message content, token usage, tool call details, session grouping, and agent identity — all formatted with OpenInference semantic conventions so Arize Phoenix can render message bubbles, token dashboards, and tool call panels. The technical approach is to enhance the existing `ReqLLMTracer` telemetry handler by (1) enabling ReqLLM's `payloads: :raw` config to make full request/response data available in telemetry events, (2) implementing OpenInference attribute flattening for messages, and (3) enriching spans with session/agent context from the existing `ObsTracer.Cache`.

## Technical Context

**Language/Version**: Elixir ≥ 1.15 on OTP  
**Primary Dependencies**: `opentelemetry_api ~> 1.5`, `req_llm ~> 1.0`, `agent_obs ~> 0.1.4`, `:telemetry ~> 1.3`  
**Storage**: ETS (in-memory span context), no database changes  
**Testing**: ExUnit with `Phoenix.LiveViewTest` and `LazyHTML`  
**Target Platform**: Linux/macOS server (Phoenix web application)  
**Project Type**: Umbrella web application with AI agent framework  
**Performance Goals**: <50ms tracing overhead per LLM call  
**Constraints**: Must not crash or degrade user-facing functionality on tracing failures  
**Scale/Scope**: Development observability tool; traces exported to local Arize Phoenix via OTLP

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| **I. Code Quality** | ✅ PASS | Single-responsibility module (ReqLLMTracer). Functions stay under 20 lines. No business logic in LiveViews. `mix precommit` enforced. |
| **II. Testing Standards** | ✅ PASS | Existing 17 tests. New tests will cover message flattening, session enrichment. No `Process.sleep`. Test file mirrors source tree. |
| **III. UX Consistency** | ✅ N/A | No UI changes. Back-end tracing only. |
| **IV. Performance** | ✅ PASS | ETS O(1) operations. OTel batch export is async. Map manipulation is microsecond-level. |
| **V. Developer Experience** | ✅ PASS | Single config line enables feature. `mix setup` unaffected. Zero-warning compilation required. |
| **Technology Constraints** | ✅ PASS | Elixir/OTP, `Req`-based HTTP (via ReqLLM), ExUnit testing. No prohibited dependencies. |
| **Dev Workflow** | ✅ PASS | `mix precommit` runs all checks. Conventional commits. No new deps needed. |

**Pre-design gate**: PASSED — no violations.

## Project Structure

### Documentation (this feature)

```text
specs/007-llm-otel-tracing/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0: research findings and decisions
├── data-model.md        # Phase 1: entity definitions and relationships
├── quickstart.md        # Phase 1: setup and verification guide
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
apps/jido_murmur/
├── lib/jido_murmur/telemetry/
│   └── req_llm_tracer.ex       # Main handler (enhance existing)
└── test/jido_murmur/telemetry/
    └── req_llm_tracer_test.exs  # Tests (enhance existing)

apps/murmur_demo/
└── lib/murmur/application.ex    # Startup (already attaches tracer)

config/
├── config.exs                   # Add req_llm telemetry payloads config
└── prod.exs                     # Disable raw payloads in production
```

**Structure Decision**: This feature modifies existing files only — no new modules or directories. All changes are within the `jido_murmur` app (tracer + tests) and config files. The handler is already attached at startup in `murmur_demo`.

## Post-Design Constitution Re-Check

| Principle | Status | Notes |
|-----------|--------|-------|
| **I. Code Quality** | ✅ PASS | Message flattening extracted to private functions. No new modules — extending existing handler. |
| **II. Testing Standards** | ✅ PASS | New tests for: input message flattening, output message flattening, tool call attributes, session/agent enrichment, empty messages edge case, large context handling. |
| **III. UX Consistency** | ✅ N/A | No UI changes. |
| **IV. Performance** | ✅ PASS | Message flattening is O(N) where N = message count. Attribute maps are flat key-value pairs. No additional network calls. |
| **V. Developer Experience** | ✅ PASS | `config :req_llm, telemetry: [payloads: :raw]` is the only new config. Quickstart doc created. |

**Post-design gate**: PASSED — no violations.

## Complexity Tracking

No constitution violations to justify. The implementation is minimal:
- Enhancing one existing module (ReqLLMTracer)
- Adding one config line
- Extending existing test file
