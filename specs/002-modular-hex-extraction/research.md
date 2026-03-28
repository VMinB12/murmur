# Research: Modular Hex Package Extraction

**Feature**: 002-modular-hex-extraction  
**Date**: 2026-03-28  
**Status**: Complete

## Research Tasks

### R1: Mix Umbrella Best Practices for Hex Publishing

**Question**: How to structure umbrella apps so each is independently publishable while sharing a lockfile and config?

**Decision**: Standard Mix umbrella with `in_umbrella: true` for development, versioned Hex deps for publishing.

**Rationale**: 
- Mix umbrellas are first-class in Elixir tooling — `mix test`, `mix compile`, `mix cmd` all work from root
- Each app under `apps/` has its own `mix.exs` with Hex metadata; `cd apps/jido_murmur && mix hex.publish` publishes independently
- The `in_umbrella: true` / Hex dep toggle pattern is well-established (Ecto/Ecto SQL use this exact approach)
- A single `mix.lock` prevents version skew across packages during development

**Implementation pattern:**
```elixir
# In apps/jido_murmur_web/mix.exs
defp deps do
  jido_murmur_dep =
    if System.get_env("HEX_PUBLISH") do
      {:jido_murmur, "~> 0.1"}
    else
      {:jido_murmur, in_umbrella: true}
    end

  [jido_murmur_dep, ...]
end
```

**Alternatives considered:**
- Separate Git repos per package — rejected: cross-package changes require multiple PRs, CI is harder, version coordination is manual
- Monorepo with `path:` deps — rejected: `in_umbrella: true` is the idiomatic Elixir approach with better tooling support
- Poncho project (flat structure) — rejected: loses umbrella tooling benefits (`mix test` from root, shared config)

---

### R2: ETS Table Namespacing in Multi-App BEAM

**Question**: How to prevent ETS table name collisions when `jido_murmur` runs alongside other apps on the same BEAM node?

**Decision**: Namespace all ETS table names with `jido_murmur_` prefix.

**Rationale**:
- Current tables: `:murmur_pending_messages`, `:murmur_active_runners` — these would collide if another app used similar names
- Prefixed names: `:jido_murmur_pending_messages`, `:jido_murmur_active_runners`
- `TableOwner` GenServer already manages table lifecycle — renaming is a one-line change per table
- ETS named tables are globally unique per BEAM node; namespacing is the standard Elixir convention

**Alternatives considered:**
- Dynamic table references (no named tables) — rejected: adds complexity to PendingQueue/Runner lookups, no real benefit
- Registry-based table discovery — rejected: over-engineering for 2 tables

---

### R3: Migration Generator Pattern for Hex Packages

**Question**: What is the best pattern for Hex packages to ship database migrations that consumers install into their projects?

**Decision**: Mix task generators that copy timestamped migration files into the consumer's `priv/repo/migrations/` directory, following the Oban pattern.

**Rationale**:
- Oban, PaperTrail, and Pow all use this same pattern successfully
- Consumer runs `mix jido_murmur.install` → migration files are generated with proper timestamps in consumer's repo
- Consumers can inspect and customize migrations before running them
- Subsequent runs detect existing migrations by module name and skip/warn
- Migration ordering is enforced via documentation and sequential timestamp gaps

**Implementation pattern:**
```elixir
defmodule Mix.Tasks.JidoMurmur.Install do
  use Mix.Task

  @migrations [
    {1, "create_jido_murmur_workspaces"},
    {2, "create_jido_murmur_agent_sessions"},
    {3, "create_jido_murmur_checkpoints"},
    {4, "create_jido_murmur_thread_entries"}
  ]

  def run(_args) do
    for {offset, name} <- @migrations do
      timestamp = generate_timestamp(offset)
      source = template_path(name)
      target = Path.join(migrations_path(), "#{timestamp}_#{name}.exs")

      if migration_exists?(name) do
        Mix.shell().info("Migration #{name} already exists, skipping.")
      else
        Mix.Generator.copy_template(source, target, [])
        Mix.shell().info("Created #{target}")
      end
    end
  end
end
```

**Alternatives considered:**
- Ecto's `@migration_source` — rejected: doesn't give consumers control over migration content
- Runtime migrations (package runs its own migrations) — rejected: surprises consumers, violates principle of least surprise
- Consolidator migrations (single file with all tables) — rejected: less granular, harder to customize

---

### R4: Application Environment Configuration for Injected Modules

**Question**: How should `jido_murmur` reference consumer-specific modules (Repo, PubSub, Jido) without hardcoding them?

**Decision**: Application environment configuration with compile-time accessors and clear error messages.

**Rationale**:
- Standard Elixir pattern used by Oban (`config :oban, repo: MyApp.Repo`), Pow, and other Hex packages
- Three required config keys: `:repo`, `:pubsub`, `:jido_mod`
- `JidoMurmur` root module provides accessor functions that fetch from app env
- Clear `ArgumentError` at startup if required config is missing

**Configuration shape:**
```elixir
config :jido_murmur,
  repo: MyApp.Repo,
  pubsub: MyApp.PubSub,
  jido_mod: MyApp.Jido,
  otp_app: :my_app,
  profiles: [MyApp.Agents.CustomerSupport, MyApp.Agents.Researcher],
  authorize: nil,  # default: no auth
  artifact_renderers: %{}  # default: generic renderer only
```

**Alternatives considered:**
- Compile-time config via `use JidoMurmur, repo: MyApp.Repo` — rejected: forces compilation order dependencies, harder to test
- Behaviour-based config module — rejected: over-engineering for simple key-value config
- Protocol-based dispatch — rejected: Elixir protocols are for polymorphism over data types, not app config

---

### R5: LLM Mock Strategy for Package Tests

**Question**: How to test LLM-dependent code without making real API calls, while supporting both built-in mock and consumer Mox stubs?

**Decision**: Ship `JidoMurmur.LLM.Mock` as a built-in mock adapter with configurable canned responses, plus document Mox usage for fine-grained control.

**Rationale**:
- The existing `Murmur.Agents.LLM` behaviour already defines `ask/4` and `await/3` callbacks
- `LLM.Mock` implements the behaviour with configurable responses (process dictionary or app env)
- In test config: `config :jido_murmur, llm_adapter: JidoMurmur.LLM.Mock`
- Consumers who need precise control can use Mox against `JidoMurmur.LLM` behaviour
- FR-020 requires zero real LLM API calls; FR-021 specifies both approaches

**Mock implementation pattern:**
```elixir
defmodule JidoMurmur.LLM.Mock do
  @behaviour JidoMurmur.LLM

  def ask(_mod, _pid, _content, _opts) do
    {:ok, make_ref()}
  end

  def await(_mod, _handle, _opts) do
    response = Process.get(:mock_llm_response, default_response())
    {:ok, response}
  end

  def set_response(response), do: Process.put(:mock_llm_response, response)
end
```

**Alternatives considered:**
- Only Mox (no built-in mock) — rejected: requires every consumer to set up Mox boilerplate for basic testing
- Bypass/HTTP interception — rejected: tests at wrong abstraction layer; we want to mock the LLM adapter, not HTTP
- Sandbox/recording approach — rejected: too complex, fragile recordings

---

### R6: Telemetry Event Design

**Question**: What telemetry events should `jido_murmur` emit, and what is the naming convention?

**Decision**: Emit `:telemetry` events at key lifecycle points using the `[:jido_murmur, ...]` prefix, following Ecto/Phoenix conventions.

**Rationale**:
- FR-022 requires telemetry at: agent start/stop, message sent, streaming signal emitted, artifact stored
- Elixir convention: `[:lib_name, :resource, :action]` with `:start`, `:stop`, `:exception` suffixes
- Measurements include timing (`:system_time`, `:duration`) and counts
- Metadata includes workspace_id, session_id, agent profile for correlation

**Event catalog:**

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:jido_murmur, :runner, :send_message, :start]` | `system_time` | `workspace_id, session_id, content_length` |
| `[:jido_murmur, :runner, :send_message, :stop]` | `duration` | `workspace_id, session_id, status` |
| `[:jido_murmur, :runner, :send_message, :exception]` | `duration` | `workspace_id, session_id, kind, reason` |
| `[:jido_murmur, :agent, :start]` | `system_time` | `workspace_id, session_id, profile_id` |
| `[:jido_murmur, :agent, :stop]` | `system_time` | `workspace_id, session_id, reason` |
| `[:jido_murmur, :streaming, :signal]` | `system_time` | `session_id, signal_type` |
| `[:jido_murmur, :artifact, :store]` | `system_time` | `session_id, artifact_name, mode` |

**Alternatives considered:**
- Custom event system (GenServer-based) — rejected: reinvents `:telemetry`; non-standard
- Logger-only observability — rejected: telemetry enables metrics aggregation; logging is for debugging

---

### R7: Per-Package Test Isolation with Shared Database

**Question**: How should test database isolation work across umbrella packages that share PostgreSQL tables?

**Decision**: Each package ships its own `TestCase` module with Ecto sandbox checkout. Umbrella shares a single test database. Packages are independently testable via `mix test --app <package_name>`.

**Rationale**:
- FR-023 requires per-package test case modules with sandbox setup
- Standard Ecto sandbox (`Ecto.Adapters.SQL.Sandbox`) handles transaction isolation per test
- The test database is created once by the demo app's `mix ecto.setup`; library packages connect to it via shared config
- Each package's `test_helper.exs` starts the sandbox and sets up package-specific test fixtures
- `mix test` from umbrella root runs all packages; `mix test --app jido_tasks` runs one

**Test helper pattern:**
```elixir
# apps/jido_murmur/test/test_helper.exs
ExUnit.start()

# The demo app or umbrella config must have started the Repo
Ecto.Adapters.SQL.Sandbox.mode(JidoMurmur.repo(), :manual)

# apps/jido_murmur/test/support/case.ex
defmodule JidoMurmur.Case do
  use ExUnit.CaseTemplate
  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(JidoMurmur.repo(), shared: !tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
```

**Alternatives considered:**
- Per-package test database — rejected: migration duplication, CI complexity, unnecessary isolation
- Mocked repos in library packages — rejected: loses integration test value; Ecto sandbox solves this cleanly
- Only umbrella-level tests — rejected: violates FR-023 requirement for independently testable packages

---

### R8: LiveView Component Delivery Strategy

**Question**: How should `jido_murmur_web` deliver LiveView components that consumers can both use directly and customize?

**Decision**: Dual-mode delivery — direct import (default) plus generator-based copy (shadcn-inspired) for full customization.

**Rationale**:
- FR-009/FR-010 require both direct-import and generator-based installation
- Direct import: `import JidoMurmurWeb.Components.ChatMessage` — works if consumer accepts default styling
- Generator: `mix jido_murmur_web.install chat` — copies component source into consumer's project
- Consumer owns copied code — can freely customize without risk of package upgrade overwriting changes (SC-007)
- Tailwind `@source` directive needed for direct import mode to pick up classes from dep path

**Generator approach:**
```elixir
defmodule Mix.Tasks.JidoMurmurWeb.Install do
  use Mix.Task

  @component_groups %{
    "chat" => ["chat_message.ex", "chat_stream.ex", "message_input.ex", "streaming_indicator.ex"],
    "workspace" => ["workspace_list.ex", "agent_selector.ex", "agent_header.ex"],
    "artifacts" => ["artifact_panel.ex"]
  }

  def run([group]) do
    files = Map.fetch!(@component_groups, group)
    target_dir = Path.join(["lib", web_module_dir(), "components", "jido_murmur"])

    for file <- files do
      source = Application.app_dir(:jido_murmur_web, "priv/templates/components/#{file}")
      target = Path.join(target_dir, file)
      Mix.Generator.copy_template(source, target, [web_module: web_module()])
    end
  end
end
```

**Alternatives considered:**
- Only direct import (no generator) — rejected: consumers can't customize deeply; FR-010 requires generator mode
- Only generator (no direct import) — rejected: too much friction for consumers who just want defaults
- Phoenix component slots for customization — rejected: insufficient for styling overrides; consumers need full source access

---

### R9: Authorization Hook Design

**Question**: How should the pluggable authorization hook work so that adding auth later is a config change, not a redesign?

**Decision**: Optional `authorize` config key pointing to a module implementing `authorize/3`. Default is `nil` (permissive — no auth checks).

**Rationale**:
- FR-013 requires pluggable auth defaulting to no-op
- SC-008 requires auth addition via config change + data migration only
- Schemas include `owner_id` field (nullable) from day one — no schema redesign needed later
- When `authorize: nil`, context functions skip auth entirely
- When configured, `authorize(action, resource, scope)` returns `:ok` or `{:error, :unauthorized}`

**Authorization flow:**
```elixir
defmodule JidoMurmur.Workspaces do
  def get_workspace!(id, scope \\ %{}) do
    workspace = JidoMurmur.repo().get!(Workspace, id)
    case authorize_fn() do
      nil -> workspace
      mod -> 
        :ok = mod.authorize(:read, workspace, scope)
        workspace
    end
  end
  
  defp authorize_fn, do: Application.get_env(:jido_murmur, :authorize)
end
```

**Alternatives considered:**
- Behaviour-based auth with mandatory implementation — rejected: forces auth boilerplate on consumers who don't need it
- Middleware/plug-based auth — rejected: auth at context level is more granular and testable than HTTP layer
- Built-in auth (Pow/phx.gen.auth) — rejected: out of scope per spec assumptions; schema is auth-ready, implementation is deferred

---

### R10: Umbrella Config Scoping Strategy

**Question**: How should config be organized across the umbrella so each package reads only its own config?

**Decision**: Shared `config/` at umbrella root with per-app scoping (`config :jido_murmur, ...`, `config :jido_tasks, ...`). The demo app merges umbrella config with its own.

**Rationale**:
- Mix umbrella automatically loads `config/config.exs` from root and merges with per-app config
- Each package reads only `Application.get_env(:its_own_app, :key)`
- Demo app config (`config :murmur, ...`) remains separate from library config
- Test config (`config/test.exs`) sets test-specific values for all apps (mock adapters, sandbox mode)

**Config organization:**
```elixir
# config/config.exs (umbrella root)
import_config "#{config_env()}.exs"

# config/dev.exs
config :jido_murmur,
  repo: Murmur.Repo,
  pubsub: Murmur.PubSub,
  jido_mod: Murmur.Jido,
  otp_app: :murmur

config :jido_tasks,
  repo: Murmur.Repo

config :murmur, Murmur.Repo,
  database: "murmur_dev",
  ...
```

**Alternatives considered:**
- Per-app config files only — rejected: harder to coordinate shared settings (Repo, PubSub)
- Runtime-only config — rejected: some config is needed at compile time (Ecto repo, endpoint)
