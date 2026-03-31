# Implementation Plan: Modular Hex Package Extraction

**Branch**: `002-modular-hex-extraction` | **Date**: 2026-03-28 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/002-modular-hex-extraction/spec.md`

## Summary

Extract Murmur's multi-agent architecture into independently publishable Hex packages organized as a Mix umbrella project. The core package `jido_murmur` provides Jido-native backend orchestration (Runner, PendingQueue, Plugins, Actions, Storage, Schemas). `jido_murmur_web` offers optional LiveView components. `jido_tasks` and `jido_arxiv` deliver domain-specific Jido Action tools. The existing Murmur application becomes `murmur_demo` — a reference app validating all packages. All components implement Jido behaviours directly (Plugin, Action, Storage) without wrapper abstractions — consumers use Jido APIs alongside the packages.

## Technical Context

**Language/Version**: Elixir >= 1.15 on OTP (current: Elixir 1.19.5, OTP 28.4.1)
**Primary Dependencies**: Phoenix 1.8.5, Jido 2.0 (jido, jido_ai, jido_signal, jido_action), req_llm ~> 1.0, phoenix_live_view ~> 1.1.0
**Storage**: PostgreSQL via Ecto SQL ~> 3.13 (Postgrex), ETS (PendingQueue, TableOwner)
**Testing**: ExUnit with Phoenix.LiveViewTest, LazyHTML, Mox ~> 1.0; 29 existing test modules
**Target Platform**: Elixir/OTP server (Linux, macOS); Phoenix web application
**Project Type**: Mix umbrella containing 4 publishable library packages + 1 demo web application
**Performance Goals**: LiveView mount < 200ms (constitution); Runner drain-loop non-blocking; configurable agent timeouts (default 30s)
**Constraints**: Zero third-party LLM API calls in tests (FR-020); 80% line coverage per package (FR-024); zero wrapper behaviours that duplicate Jido interfaces (SC-005)
**Scale/Scope**: 5 umbrella apps, ~35 modules to relocate, 7 database tables, 29 existing test files to redistribute

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Code Quality — single responsibility, short functions, contexts encapsulate logic | PASS | Extraction improves this — each package has clearer boundaries than the monolith |
| I. Code Quality — YAGNI, no abstractions for hypothetical needs | PASS | No wrapper behaviours; `ComposableRequestTransformer` solves a concrete current limitation |
| I. Code Quality — simple solutions preferred | PASS | Config-driven Catalog (convention over behaviour), config map for renderers |
| II. Testing — every feature ships with tests, deterministic, fast | PASS | Per-package test suites; shared Ecto sandbox; Mox for LLM adapter; no Process.sleep |
| II. Testing — test files mirror source tree | PASS | Each package has its own `test/` mirroring `lib/` |
| III. UX Consistency — core components, streams for collections | PASS | LiveView components in `jido_murmur_web` reuse core_components patterns |
| IV. Performance — LiveView mount < 200ms, preload associations, streams | PASS | No architectural changes to LiveView patterns |
| V. Developer Experience — `mix setup` single command, frictionless workflow | PASS | Umbrella `mix setup` from root; per-app `mix test --app <name>` |
| V. Developer Experience — no indirection/unnecessary abstractions | PASS | Jido-native design explicitly avoids wrapping Jido APIs |
| Technology Constraints — Elixir/Phoenix/Ecto/Tailwind/esbuild/Req/Jido 2.0 | PASS | All maintained; no new tech stack additions |
| Development Workflow — `mix precommit`, conventional commits, CI | PASS | Umbrella-level precommit; per-app coverage gates |

**Gate result: PASS** — no violations. Constitution is fully compatible with umbrella extraction.

## Project Structure

### Documentation (this feature)

```text
specs/002-modular-hex-extraction/
├── plan.md              # This file
├── research.md          # Phase 0 output — resolved unknowns
├── data-model.md        # Phase 1 output — entity schemas & relationships
├── quickstart.md        # Phase 1 output — consumer integration guide
├── contracts/           # Phase 1 output — PubSub and public API contracts
│   ├── pubsub.md
│   └── public-api.md
└── tasks.md             # Phase 2 output (NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
murmur/                                        # Umbrella root
├── apps/
│   ├── jido_murmur/                           # Core backend package
│   │   ├── lib/jido_murmur/
│   │   │   ├── runner.ex                      # Ask/await drain-loop orchestration
│   │   │   ├── pending_queue.ex               # ETS-backed message queue
│   │   │   ├── table_owner.ex                 # ETS table lifecycle GenServer
│   │   │   ├── message_injector.ex            # ReAct.RequestTransformer impl
│   │   │   ├── composable_request_transformer.ex  # Multi-transformer chain
│   │   │   ├── team_instructions.ex           # Dynamic multi-agent prompt builder
│   │   │   ├── streaming_plugin.ex            # Jido.Plugin — signal → PubSub
│   │   │   ├── artifact_plugin.ex             # Jido.Plugin — artifact signals
│   │   │   ├── artifact.ex                    # Artifact signal helpers
│   │   │   ├── tell_action.ex                 # Jido.Action — inter-agent messaging
│   │   │   ├── catalog.ex                     # Config-driven profile registry
│   │   │   ├── ui_turn.ex                     # Thread → UI display projection
│   │   │   ├── agent_helper.ex                # Convenience functions (not a facade)
│   │   │   ├── supervisor.ex                  # Supervision tree component
│   │   │   ├── llm.ex                         # LLM adapter behaviour
│   │   │   ├── llm/
│   │   │   │   ├── real.ex                    # Production LLM adapter
│   │   │   │   └── mock.ex                    # Test mock adapter (FR-021)
│   │   │   ├── actions/
│   │   │   │   └── store_artifact.ex          # Artifact persistence action
│   │   │   ├── storage/
│   │   │   │   ├── ecto.ex                    # Jido.Storage implementation
│   │   │   │   ├── checkpoint.ex              # Ecto schema
│   │   │   │   └── thread_entry.ex            # Ecto schema
│   │   │   ├── workspaces/
│   │   │   │   ├── workspace.ex               # Ecto schema
│   │   │   │   └── agent_session.ex           # Ecto schema
│   │   │   └── workspaces.ex                  # Context (CRUD)
│   │   ├── lib/jido_murmur.ex                 # Config accessors (repo/pubsub/jido)
│   │   ├── lib/mix/tasks/
│   │   │   └── jido_murmur.install.ex         # Migration generator
│   │   ├── priv/templates/                    # Migration templates
│   │   ├── mix.exs
│   │   └── test/
│   │
│   ├── jido_murmur_web/                       # Optional LiveView components
│   │   ├── lib/jido_murmur_web/
│   │   │   ├── components/
│   │   │   │   ├── chat_message.ex
│   │   │   │   ├── chat_stream.ex
│   │   │   │   ├── agent_header.ex
│   │   │   │   ├── message_input.ex
│   │   │   │   ├── streaming_indicator.ex
│   │   │   │   ├── agent_selector.ex
│   │   │   │   ├── workspace_list.ex
│   │   │   │   └── artifact_panel.ex
│   │   │   └── components.ex                  # Unified import module
│   │   ├── lib/mix/tasks/
│   │   │   └── jido_murmur_web.install.ex     # Component copy generator
│   │   ├── mix.exs
│   │   └── test/
│   │
│   ├── jido_tasks/                            # Task management tools
│   │   ├── lib/jido_tasks/
│   │   │   ├── task.ex                        # Ecto schema
│   │   │   ├── tasks.ex                       # Context (CRUD, stats)
│   │   │   └── tools/
│   │   │       ├── add_task.ex                # Jido.Action
│   │   │       ├── update_task.ex             # Jido.Action
│   │   │       └── list_tasks.ex              # Jido.Action
│   │   ├── lib/jido_tasks.ex
│   │   ├── lib/mix/tasks/
│   │   │   └── jido_tasks.install.ex          # Migration generator
│   │   ├── priv/templates/
│   │   ├── mix.exs
│   │   └── test/
│   │
│   ├── jido_arxiv/                            # Academic research tools
│   │   ├── lib/jido_arxiv/
│   │   │   └── tools/
│   │   │       ├── arxiv_search.ex            # Jido.Action
│   │   │       └── display_paper.ex           # Jido.Action
│   │   ├── lib/jido_arxiv.ex
│   │   ├── mix.exs
│   │   └── test/
│   │
│   └── murmur_demo/                           # Reference application
│       ├── lib/murmur/
│       │   ├── application.ex
│       │   ├── repo.ex
│       │   ├── jido.ex                        # use Jido, otp_app: :murmur
│       │   └── agents/profiles/
│       │       ├── general_agent.ex
│       │       └── arxiv_agent.ex
│       ├── lib/murmur_web/
│       │   ├── endpoint.ex
│       │   ├── router.ex
│       │   ├── telemetry.ex
│       │   ├── components/
│       │   │   ├── core_components.ex
│       │   │   ├── layouts.ex
│       │   │   └── artifacts.ex
│       │   ├── live/
│       │   │   ├── workspace_live.ex
│       │   │   └── workspace_list_live.ex
│       │   └── helpers/
│       │       └── markdown.ex
│       ├── assets/                            # JS/CSS (esbuild + tailwind)
│       ├── config/                            # App-specific config
│       ├── priv/
│       │   ├── repo/migrations/               # All migrations (generated + app-specific)
│       │   └── static/
│       ├── mix.exs                            # in_umbrella: true deps
│       └── test/
│
├── config/                                    # Shared umbrella config
│   ├── config.exs
│   ├── dev.exs
│   ├── test.exs
│   ├── prod.exs
│   └── runtime.exs
├── mix.exs                                    # Umbrella root
└── mix.lock                                   # Single shared lockfile
```

**Structure Decision**: Mix umbrella project with 5 apps. Each library package (`jido_murmur`, `jido_murmur_web`, `jido_tasks`, `jido_arxiv`) is independently publishable to Hex. The `murmur_demo` app validates all packages via `in_umbrella: true` dependencies. Config is scoped per-app (`config :jido_murmur, ...`). A single `mix.lock` ensures dependency version consistency across all packages.

## Complexity Tracking

No constitution violations to justify. The umbrella structure with 5 apps is the minimum needed to deliver independently publishable packages (4 libraries) while maintaining a demo/reference app (1 application). Each package maps directly to a spec requirement.
