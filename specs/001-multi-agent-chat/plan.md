# Implementation Plan: Multi-Agent Chat Interface

**Branch**: `001-multi-agent-chat` | **Date**: 2026-03-25 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-multi-agent-chat/spec.md`

## Summary

Build a real-time multi-agent chat application where users construct a team of AI agents in a workspace. Each agent runs as a Jido AgentServer (GenServer), streams LLM responses token-by-token via PubSub to a Phoenix LiveView, and can communicate with other agents via a "tell" tool. Persistence is per-agent, per-turn via Ecto/PostgreSQL. The LiveView renders agents as side-by-side scrollable columns using Phoenix Streams.

## Technical Context

**Language/Version**: Elixir ≥ 1.15 on OTP  
**Primary Dependencies**: Phoenix 1.8, Phoenix LiveView 1.1, Jido 2.0, Jido.AI 2.0, Jido.Action, Jido.Signal, ReqLLM, Ecto SQL 3.13, Postgrex  
**Storage**: PostgreSQL via Ecto  
**Testing**: ExUnit with `Phoenix.LiveViewTest` and `LazyHTML`  
**Target Platform**: Web (desktop browsers ≥ 1024px)  
**Project Type**: Web application (Phoenix LiveView)  
**Performance Goals**: Mount < 200ms; token streaming with no perceptible lag; 5 concurrent agents without UI degradation  
**Constraints**: < 200ms LiveView mount; per-turn persistence (not per-token); maximum 8 agents per workspace; 5-hop inter-agent loop depth limit  
**Scale/Scope**: Single-user local/dev instance for v1; hardcoded agent catalog

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Principle | Status | Notes |
|------|-----------|--------|-------|
| G1 | I. Code Quality — Single responsibility | ✅ PASS | Contexts (Workspaces, Chat) encapsulate domain logic; LiveView handles only UI |
| G2 | I. Code Quality — YAGNI | ✅ PASS | No auth, no mobile, no dynamic catalog; minimal scope |
| G3 | II. Testing — LiveViewTest with element IDs | ✅ PASS | Plan includes LiveView tests for all user stories |
| G4 | III. UX — Use core components, Layouts.app, Streams | ✅ PASS | All collections via streams; forms via `<.input>`; `<Layouts.app>` wrapper |
| G5 | IV. Performance — Mount < 200ms, no N+1 | ✅ PASS | Mount loads from GenServer state (in-memory); preload associations in Ecto queries |
| G6 | IV. Performance — Streams over list assigns | ✅ PASS | Message history rendered via `phx-update="stream"` |
| G7 | V. DX — mix setup, mix precommit | ✅ PASS | Standard Phoenix setup; migrations generated via `mix ecto.gen.migration` |
| G8 | Technology — Jido 2.0, Req, Tailwind v4 | ✅ PASS | All deps already in mix.exs; no new HTTP client needed |

All gates pass. No violations to justify.

## Project Structure

### Documentation (this feature)

```text
specs/001-multi-agent-chat/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── pubsub.md        # PubSub topic & payload contracts
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
lib/
├── murmur/
│   ├── application.ex            # Supervision tree (existing, add Jido)
│   ├── repo.ex                   # Ecto repo (existing)
│   ├── jido.ex                   # Jido supervisor (existing)
│   ├── workspaces/               # Workspaces context
│   │   ├── workspace.ex          # Ecto schema
│   │   └── agent_session.ex      # Ecto schema
│   ├── chat/                     # Chat context
│   │   ├── message.ex            # Ecto schema
│   │   └── chat.ex               # Context module (queries, persistence)
│   └── agents/                   # Agent domain
│       ├── catalog.ex            # Profile registry: maps IDs to {module, display_meta}
│       ├── tell_action.ex        # Jido Action for inter-agent "tell"
│       └── profiles/             # Jido.AI.Agent modules per profile
│           ├── sql_agent.ex      # use Jido.AI.Agent, model: ..., tools: [...]
│           └── arxiv_agent.ex
├── murmur_web/
│   ├── router.ex                 # Add workspace routes
│   ├── components/
│   │   ├── core_components.ex    # Existing
│   │   └── layouts.ex            # Existing
│   └── live/
│       ├── workspace_live.ex     # Main workspace LiveView
│       └── workspace_live.html.heex  # Template

priv/
└── repo/
    └── migrations/
        ├── *_create_workspaces.exs
        ├── *_create_agent_sessions.exs
        └── *_create_messages.exs

test/
├── murmur/
│   ├── workspaces_test.exs
│   ├── chat_test.exs
│   └── agents/
│       ├── catalog_test.exs
│       └── tell_action_test.exs
└── murmur_web/
    └── live/
        └── workspace_live_test.exs
```

**Structure Decision**: Standard Phoenix single-project layout. Domain logic split into three contexts: `Workspaces` (workspace + session CRUD), `Chat` (message persistence and queries), and `Agents` (runtime execution via Jido). Agent profiles are `Jido.AI.Agent` modules started directly via `Murmur.Jido.start_agent/2` — no wrapper GenServer needed since `Jido.AgentServer` is the runtime. This follows Phoenix convention and the constitution's single-responsibility and avoid-indirection principles.

## Complexity Tracking

No constitution violations. Table intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
