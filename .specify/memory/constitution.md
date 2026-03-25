<!--
  Sync Impact Report
  ===================
  Version change: 1.0.0 → 1.1.0 (MINOR — new DX principle added)
  Modified principles:
    - I. Code Quality: added clarity/readability DX bullet
    - II. Testing Standards: added fast-feedback DX bullets
    - IV. Performance: added dev-mode reload speed bullet
  Added sections:
    - V. Developer Experience (new principle)
  Removed sections: None
  Templates requiring updates:
    - .specify/templates/plan-template.md ✅ compatible
    - .specify/templates/spec-template.md ✅ compatible
    - .specify/templates/tasks-template.md ✅ compatible
  Follow-up TODOs: None
-->

# Murmur Constitution

## Core Principles

### I. Code Quality

All code MUST pass Credo strict analysis and Dialyxir checks
before merge. Run `mix precommit` to verify.

- Every module MUST have a clear, single responsibility
- Functions MUST be short and composable; extract a new function
  when a function body exceeds ~20 lines
- Phoenix contexts MUST encapsulate domain logic; LiveViews and
  controllers MUST NOT contain business rules directly
- Ecto changesets MUST validate at the boundary; programmatic
  fields (e.g. `user_id`) MUST NOT appear in `cast/3` calls
- Pattern matching and `with` MUST be preferred over nested
  conditionals; avoid deep nesting
- Simple solutions MUST be preferred over clever ones; do not
  add abstractions, helpers, or configuration for hypothetical
  future needs (YAGNI)
- Code MUST be written for the next reader; prefer explicit
  names, small modules, and obvious flow over terse cleverness
- Do not add needless backwards compatibility. If a change improves the codebase and the impact is justified, it should be made without hesitation. Avoid maintaining legacy code paths that add complexity and technical debt when they no longer serve a clear purpose.

### II. Testing Standards

Every user-facing feature MUST ship with tests that verify
observable outcomes. Tests MUST be deterministic and fast.

- LiveView features MUST include `Phoenix.LiveViewTest`
  assertions using element IDs and `has_element?/2`
- Context modules MUST have unit tests covering success paths
  and key error paths
- Tests MUST NOT use `Process.sleep/1`; use `Process.monitor/1`
  or `:sys.get_state/1` for synchronization
- Test files MUST mirror the source tree
  (e.g. `lib/murmur/chat.ex` → `test/murmur/chat_test.exs`)
- Database-dependent tests MUST use `Ecto.Adapters.SQL.Sandbox`
- Tests MUST assert behavior, not implementation; avoid testing
  raw HTML strings—use `LazyHTML` selectors instead
- The full test suite SHOULD complete in under 60 seconds; slow
  tests erode the feedback loop and MUST be optimized or tagged
- Running a single test file (`mix test path/to/test.exs`) MUST
  work in isolation without extra setup steps

### III. User Experience Consistency

The UI MUST feel cohesive, responsive, and polished across
every page. Reuse core components; avoid one-off styling.

- All forms MUST use the imported `<.input>` and `<.form>`
  components from `core_components.ex`
- All icons MUST use the `<.icon>` component; third-party icon
  modules are forbidden
- LiveView templates MUST begin with
  `<Layouts.app flash={@flash} ...>`
- Collections MUST use LiveView streams; raw list assigns for
  rendered collections are forbidden
- Tailwind CSS classes MUST be the sole styling mechanism; no
  inline styles or `@apply` directives
- Interactive elements MUST have visible hover/focus states and
  smooth transitions for a premium feel
- Pages MUST be responsive from mobile (375px) to desktop

### IV. Performance Requirements

Pages MUST load fast and stay fast. Measure before optimizing,
but enforce guardrails from the start.

- LiveView mount MUST complete in under 200ms; defer expensive
  work to `handle_async/3` or connected callbacks
- Ecto queries MUST preload associations accessed in templates;
  N+1 queries are forbidden
- Database queries MUST use indexes for filtered or sorted
  columns; new migrations MUST include indexes for foreign keys
- LiveView streams MUST be used instead of large list assigns to
  prevent memory bloat
- Static assets MUST be fingerprinted and served with long-lived
  cache headers (Phoenix default)
- `Req` MUST be used for all external HTTP calls; alternative
  HTTP clients are forbidden
- Dev-mode live reload MUST remain fast; avoid heavyweight
  compile-time macros or code generation that slows iteration

### V. Developer Experience

The development workflow MUST be frictionless. If a common task
takes more than one command or requires tribal knowledge, automate
or document it.

- `mix setup` MUST bring a fresh clone to a fully working state
  (deps, DB creation, migrations, seeds) in a single command
- `mix precommit` MUST be the only command needed before commit;
  it MUST run format, compile, credo, dialyzer, and tests
- Error messages and compiler warnings MUST be resolved
  immediately; a zero-warning policy keeps the signal-to-noise
  ratio high
- Hot code reload via `phoenix_live_reload` MUST work reliably;
  changes to templates, CSS, and Elixir code MUST reflect in the
  browser within seconds
- Generator outputs (`mix phx.gen.*`, `mix ecto.gen.migration`)
  MUST be used as starting points; never hand-craft boilerplate
  that a generator provides
- Local dev MUST require only Elixir, Erlang, and PostgreSQL;
  avoid extra services or containers unless the feature demands
  them
- Documentation for setup, architecture decisions, and non-obvious
  patterns MUST live in the repo (README, AGENTS.md, or inline
  `@moduledoc`); never rely on out-of-band knowledge
- Avoid indirection and unnecessary abstractions that make it harder for new contributors to understand the codebase; prefer straightforward, explicit code over clever patterns.

## Technology Constraints

The following stack decisions are fixed and MUST NOT be changed
without a constitution amendment.

- **Language**: Elixir ≥ 1.15 on OTP
- **Framework**: Phoenix 1.8 with LiveView 1.1
- **Database**: PostgreSQL via Ecto SQL
- **CSS**: Tailwind CSS v4 (no `tailwind.config.js`)
- **JS bundling**: esbuild; no Webpack or Vite
- **HTTP client**: `Req` (`:req`); `:httpoison`, `:tesla`, and
  `:httpc` are forbidden
- **Linting**: Credo (strict mode) + Dialyxir
- **Testing**: ExUnit with `Phoenix.LiveViewTest` and `LazyHTML`
- **Agent framework**: Jido 2.0

## Development Workflow

Quality gates MUST be enforced at every stage of delivery.

- **Before commit**: Run `mix precommit` — a single command
  that compiles, formats, runs credo, dialyzer, and tests.
  Git hooks enforce this automatically
- **Pull requests**: MUST pass CI (same checks as precommit).
  All new LiveView routes MUST include at least one LiveView
  test
- **Migrations**: MUST be generated with
  `mix ecto.gen.migration` for correct timestamps. Destructive
  migrations (drop table/column) require explicit approval
- **Dependencies**: New deps MUST be justified. Prefer stdlib
  and existing deps before adding new ones
- **Commit messages**: Use conventional commits
  (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`)

## Governance

This constitution is the authoritative source of engineering
standards for Murmur. It supersedes ad-hoc decisions and
informal conventions.

- All code reviews MUST verify compliance with these principles
- Violations MUST be resolved before merge; no exceptions
  without a documented justification in the PR description
- Amendments follow semantic versioning:
  - **MAJOR**: Principle removal or backward-incompatible
    redefinition
  - **MINOR**: New principle or materially expanded guidance
  - **PATCH**: Clarifications, typo fixes, non-semantic changes
- Amendment process: propose change → review → update this
  file → bump version → commit with
  `docs: amend constitution to vX.Y.Z`

**Version**: 1.1.0 | **Ratified**: 2026-03-25 | **Last Amended**: 2026-03-25
