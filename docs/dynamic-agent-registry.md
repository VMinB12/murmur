# Dynamic Agent Registry

**Status:** Proposal  
**Date:** 2026-03-27

## Problem

Agent profiles are hardcoded in `Murmur.Agents.Catalog` as a compile-time map:

```elixir
@profiles %{
  "general_agent" => {Murmur.Agents.Profiles.GeneralAgent, %{description: "...", color: "blue"}},
  "arxiv_agent"   => {Murmur.Agents.Profiles.ArxivAgent,   %{description: "...", color: "violet"}}
}
```

Adding a new agent requires editing **three places**:

1. Create the profile module (`lib/murmur/agents/profiles/new_agent.ex`)
2. Register it in the `@profiles` map in `catalog.ex`
3. Duplicate the description metadata (already declared in the module via `use Jido.AI.Agent, description: "..."`)

The catalog also duplicates metadata that already exists inside each agent module — every `Jido.AI.Agent` module already exposes `name/0`, `description/0`, and `tags/0` at compile time.

### Touchpoints that reference agent profile IDs today

| File | How it uses profiles |
|------|---------------------|
| `lib/murmur/agents/catalog.ex` | Hardcoded `@profiles` map, lookup functions |
| `lib/murmur/agents/runner.ex` | `Catalog.agent_module(session.agent_profile_id)` to dispatch |
| `lib/murmur/agents/team_instructions.ex` | `Catalog.get_profile!(id).description` for roster |
| `lib/murmur_web/live/workspace_live.ex` | `Catalog.list_profiles()` for the add-agent modal; `Catalog.agent_module()` for lifecycle |
| `lib/murmur/workspaces/agent_session.ex` | Stores `agent_profile_id` as a string field |
| Tests (catalog, workspaces, edge_case) | Assert against specific profile IDs |

---

## Approaches

### Option A: Compile-Time Auto-Discovery (Recommended)

**Mechanism:** Use `@after_compile` or a custom Mix compiler to scan all modules under `Murmur.Agents.Profiles.*` that `use Jido.AI.Agent`, and build the registry automatically.

**How it works:**

1. Each agent profile module remains a standalone file under `lib/murmur/agents/profiles/` and declares all its metadata via `use Jido.AI.Agent`:

   ```elixir
   defmodule Murmur.Agents.Profiles.NewAgent do
     use Jido.AI.Agent,
       name: "new_agent",
       description: "Does something cool",
       tags: [:research],
       # ... tools, plugins, etc.
   end
   ```

2. The catalog discovers all profile modules at compile time by pattern-matching on a behaviour or function:

   ```elixir
   defmodule Murmur.Agents.Catalog do
     @profile_modules [
       # Populated by a compile-time discovery function
     ]
   ```

   **Practical implementation:** Use a `Mix.Task.Compiler` or a simpler approach — a compile-time function that walks `:application.get_key(:murmur, :modules)` and filters for modules that export `name/0` under the `Murmur.Agents.Profiles` namespace. Since `:application.get_key/2` only works at runtime, we'd use a two-phase approach:

   - **Phase A (simplest):** Keep an explicit list of modules in catalog.ex but derive all metadata from the modules themselves:

     ```elixir
     @profile_modules [
       Murmur.Agents.Profiles.GeneralAgent,
       Murmur.Agents.Profiles.ArxivAgent,
     ]
     ```

     Metadata (description, name) is pulled from each module's generated functions. Adding a new agent means: create the file + add one line to the list. No metadata duplication.

   - **Phase B (fully dynamic):** A runtime discovery function that scans loaded modules:

     ```elixir
     def discover_profiles do
       {:ok, modules} = :application.get_key(:murmur, :modules)
       modules
       |> Enum.filter(&profile_module?/1)
       |> Enum.map(&build_profile/1)
     end

     defp profile_module?(mod) do
       String.starts_with?(to_string(mod), "Elixir.Murmur.Agents.Profiles.") and
         function_exported?(mod, :name, 0) and
         function_exported?(mod, :description, 0)
     end
     ```

3. Display metadata (color, icon, category) is added to each agent module via a Murmur-specific extension — either a `@murmur_color "violet"` module attribute read at compile time, or a simple callback:

   ```elixir
   defmodule Murmur.Agents.Profiles.ArxivAgent do
     use Jido.AI.Agent, name: "arxiv_agent", ...

     def catalog_meta, do: %{color: "violet", icon: "hero-academic-cap"}
   end
   ```

**Tradeoffs:**

| Pro | Con |
|-----|-----|
| Single source of truth per agent — no duplication | Phase B has a small startup cost (module scan) |
| Adding an agent = 1 file (Phase B) or 1 file + 1 line (Phase A) | Phase B relies on runtime introspection, slightly harder to reason about |
| Leverages existing `Jido.AI.Agent` metadata | Need a convention for Murmur-specific metadata (color) |
| No external dependencies | Module naming convention must be enforced |
| Easy to test — just assert on the discovered list | |
| Compatible with hot code reloading in dev | |

---

### Option B: Behaviour-Based Registry with Explicit Registration

**Mechanism:** Define a `Murmur.Agents.Profile` behaviour that each agent must implement. The catalog collects implementations via an explicit registration macro.

**How it works:**

1. Define the behaviour:

   ```elixir
   defmodule Murmur.Agents.Profile do
     @callback profile_id() :: String.t()
     @callback description() :: String.t()
     @callback color() :: String.t()
     @callback agent_module() :: module()
   end
   ```

2. Each profile implements the behaviour:

   ```elixir
   defmodule Murmur.Agents.Profiles.ArxivAgent do
     @behaviour Murmur.Agents.Profile
     use Jido.AI.Agent, name: "arxiv_agent", ...

     @impl true
     def profile_id, do: "arxiv_agent"
     @impl true
     def description, do: "Research assistant with arXiv"
     @impl true
     def color, do: "violet"
     @impl true
     def agent_module, do: __MODULE__
   end
   ```

3. Registration via `@after_compile` or compile-time accumulation (Phoenix-style):

   ```elixir
   defmodule Murmur.Agents.Catalog do
     use Murmur.Agents.Registry

     register Murmur.Agents.Profiles.GeneralAgent
     register Murmur.Agents.Profiles.ArxivAgent
   end
   ```

**Tradeoffs:**

| Pro | Con |
|-----|-----|
| Compile-time guarantees via `@behaviour` | More boilerplate per agent (must implement 4 callbacks) |
| Explicit registration — clear what's included | Duplicates info already in `Jido.AI.Agent` (name, description) |
| Easy to enforce required metadata | Still requires editing catalog for registration |
| Works well with dialyzer | Over-engineered for current scale |

---

### Option C: Config-Driven Registry

**Mechanism:** Define agents in application config (`config.exs`) and have the catalog read from config at startup.

**How it works:**

```elixir
# config/config.exs
config :murmur, :agent_profiles, [
  %{id: "general_agent", module: Murmur.Agents.Profiles.GeneralAgent, color: "blue"},
  %{id: "arxiv_agent", module: Murmur.Agents.Profiles.ArxivAgent, color: "violet"}
]
```

```elixir
defmodule Murmur.Agents.Catalog do
  def list_profiles do
    Application.get_env(:murmur, :agent_profiles, [])
    |> Enum.map(fn %{id: id, module: mod} = cfg ->
      %{id: id, description: mod.description(), color: cfg.color}
    end)
  end
end
```

**Tradeoffs:**

| Pro | Con |
|-----|-----|
| Familiar Phoenix pattern | Config is yet another place to update |
| Environment-specific agent sets (e.g., test vs prod) | Configuration scattered across files |
| Easy to disable agents without deleting code | No compile-time validation of module existence |
| Supports runtime reconfiguration | Descriptions still duplicated if not pulled from modules |

---

### Option D: ETS / Runtime GenServer Registry

**Mechanism:** A GenServer-backed registry where agents register themselves at application startup. Profile modules call `Catalog.register(__MODULE__)` in their `__using__` macro or an `Application.start` callback.

**How it works:**

```elixir
defmodule Murmur.Agents.Catalog do
  use GenServer

  def register(module) do
    GenServer.call(__MODULE__, {:register, module})
  end

  def list_profiles do
    GenServer.call(__MODULE__, :list)
  end
end
```

**Tradeoffs:**

| Pro | Con |
|-----|-----|
| Truly dynamic — agents can register/unregister at runtime | Over-engineered for a compile-time-known set of agents |
| Supports hot-loading new agent modules | Registration order/timing issues |
| Future-proof for plugin-based agents | Harder to test — depends on process state |
| | Race conditions on startup |
| | ETS table already used for pending queue — adds complexity |

---

## Recommendation

**Option A, Phase A first, evolve to Phase B when needed.**

The simplest approach that eliminates the core problem:

1. **Keep an explicit module list** in `catalog.ex` (1 line per agent — just the module name)
2. **Derive all metadata** from each module's existing `name/0` and `description/0` functions
3. **Add a `catalog_meta/0` callback** for Murmur-specific display metadata (color, icon)
4. **Eliminate the `@profiles` map** — it becomes computed from the module list

### What changes

```
Before (adding an agent):
  1. Create lib/murmur/agents/profiles/new_agent.ex
  2. Edit catalog.ex — add entry to @profiles with module + description + color
  → 2 files, metadata duplicated

After (adding an agent):
  1. Create lib/murmur/agents/profiles/new_agent.ex (with catalog_meta/0)
  2. Edit catalog.ex — add module to @profile_modules list
  → 2 files, no duplication, one-liner addition to catalog

After Phase B (fully dynamic):
  1. Create lib/murmur/agents/profiles/new_agent.ex
  → 1 file, zero registration needed
```

### Migration path to Phase B

When the number of agents grows (say 10+), switch to runtime discovery:

- Replace the `@profile_modules` list with `discover_profiles/0`
- Use `Application.get_key(:murmur, :modules)` to scan at startup
- Cache the result in a module attribute or persistent_term for performance
- Convention: any module under `Murmur.Agents.Profiles.*` that exports `name/0` is an agent

This is a backward-compatible evolution — no schema changes, no config changes, just a different source for the module list.

### Concrete implementation sketch (Phase A)

```elixir
defmodule Murmur.Agents.Catalog do
  @moduledoc "Auto-discovers agent profiles from registered modules."

  @profile_modules [
    Murmur.Agents.Profiles.GeneralAgent,
    Murmur.Agents.Profiles.ArxivAgent,
  ]

  @color_palette ~w(blue emerald violet amber rose cyan fuchsia lime)
  @color_map %{ ... }  # unchanged

  def list_profiles do
    Enum.map(@profile_modules, fn mod ->
      meta = mod.catalog_meta()
      %{id: mod.name(), description: mod.description(), color: meta.color}
    end)
  end

  def get_profile!(id) do
    case find_module(id) do
      nil -> raise "Unknown agent profile: #{id}"
      mod ->
        meta = mod.catalog_meta()
        %{id: id, agent_module: mod, description: mod.description(), color: meta.color}
    end
  end

  def agent_module(profile_id) do
    case find_module(profile_id) do
      nil -> raise "Unknown agent profile: #{profile_id}"
      mod -> mod
    end
  end

  defp find_module(profile_id) do
    Enum.find(@profile_modules, fn mod -> mod.name() == profile_id end)
  end

  # color_classes/1 and agent_color/2 unchanged
end
```

Each agent adds a simple function:

```elixir
defmodule Murmur.Agents.Profiles.ArxivAgent do
  use Jido.AI.Agent,
    name: "arxiv_agent",
    description: "Research assistant with arXiv paper search and display",
    ...

  def catalog_meta, do: %{color: "violet"}
end
```

### What stays the same

- `AgentSession` schema (stores `agent_profile_id` string — the `name()` value)
- `Runner`, `TeamInstructions`, `WorkspaceLive` — all call `Catalog.*` functions unchanged
- Color system — unchanged
- All existing tests — profile IDs remain the same strings

### Non-goals (for now)

- **Hot-loading agents in production** — BEAM supports it but adds operational complexity we don't need yet.
- **Per-user agent sets** — all agents are available to all users. Access control is a separate concern.

---

## Future: User-Defined Agents (Data-Driven)

A future goal is letting users create their own agent types at runtime by selecting tools and writing a system prompt — without writing Elixir code. This changes the problem fundamentally: **user-defined agents are data, not compiled modules.**

### Why this is different from built-in agents

Built-in agents are compiled modules (`use Jido.AI.Agent`) that generate `ask/2`, `await/2`, `name/0`, etc. at compile time. User-defined agents can't use macros — they exist only as database rows with a system prompt and a tool list.

However, the architecture already has the pieces to support this:

1. **`Jido.start_agent/2` accepts `module() | struct()`** — it can start an agent from a pre-configured struct, not just a module.
2. **`ask/await` are module-level functions** — called as `agent_module.ask(pid, content, ...)` in `LLM.Real`. This is the main coupling point.

### Architecture for user-defined agents

The approach is a **generic configurable agent module** that acts as a runtime vessel:

```elixir
defmodule Murmur.Agents.Profiles.CustomAgent do
  use Jido.AI.Agent,
    name: "custom_agent",
    description: "User-configured agent",
    tools: [],  # base set; runtime tools injected per-request
    plugins: [Murmur.Agents.StreamingPlugin, Murmur.Agents.ArtifactPlugin],
    request_transformer: Murmur.Agents.MessageInjector,
    system_prompt: ""  # overridden at runtime
end
```

User-defined agent definitions are stored in the database:

```elixir
schema "agent_definitions" do
  field :name, :string           # "my_code_reviewer"
  field :display_name, :string   # "Code Reviewer"
  field :description, :string    # "Reviews PRs for style and bugs"
  field :system_prompt, :string  # The user-written prompt
  field :tool_ids, {:array, :string}  # ["arxiv_search", "display_paper"]
  field :model, :string          # "fast" or "capable"
  field :color, :string          # "rose"

  belongs_to :user, Murmur.Accounts.User  # or workspace-scoped
  timestamps()
end
```

When starting a user-defined agent, the system:

1. Loads the definition from the DB
2. Resolves `tool_ids` to actual tool modules (from a tool registry)
3. Starts `CustomAgent` with runtime overrides:

```elixir
# In runner/workspace_live:
Murmur.Jido.start_agent(CustomAgent, id: session.id)

# ask with per-request overrides:
CustomAgent.ask(pid, content,
  tool_context: tool_ctx,
  tools: resolved_tool_modules,        # per-request tool override
  system_prompt: definition.system_prompt  # if supported by Jido
)
```

### How this affects the catalog design

The catalog needs to serve **two kinds of profiles**:

| | Built-in | User-defined |
|---|---|---|
| Source | Compiled module | Database row |
| Agent module | The profile module itself | `Murmur.Agents.Profiles.CustomAgent` |
| Metadata | `mod.name()`, `mod.description()` | DB fields |
| Tools | Compiled into module | Resolved at runtime from tool registry |
| System prompt | Compiled into module | DB field |

The catalog API stays the same (`list_profiles/0`, `get_profile!/1`, `agent_module/1`), but internally it merges two sources:

```elixir
def list_profiles do
  built_in = Enum.map(@profile_modules, &built_in_profile/1)
  custom = list_custom_profiles()  # from DB
  built_in ++ custom
end

def agent_module(profile_id) do
  case find_built_in(profile_id) do
    nil -> Murmur.Agents.Profiles.CustomAgent  # all custom agents use the generic module
    mod -> mod
  end
end
```

### Impact on the Phase A recommendation

**Phase A remains the correct first step.** It doesn't conflict with user-defined agents because:

1. The catalog's public API (`list_profiles`, `get_profile!`, `agent_module`) is an **abstraction layer** — consumers don't care whether profiles come from modules or a database.
2. The `agent_profile_id` stored in `AgentSession` is just a string — it works for both `"arxiv_agent"` (built-in) and `"custom_abc123"` (user-defined).
3. Adding custom agent support later means: (a) create the `CustomAgent` generic module, (b) add an `agent_definitions` table, (c) extend `Catalog.list_profiles` to merge DB entries, (d) create a tool registry mapping string IDs to modules.

No Phase A design decisions need to be reversed.

### Tool registry (needed for user-defined agents)

Users select tools by name, so you need a registry mapping tool IDs to modules:

```elixir
defmodule Murmur.Agents.ToolRegistry do
  @tools %{
    "arxiv_search" => Murmur.Agents.Tools.ArxivSearch,
    "display_paper" => Murmur.Agents.Tools.DisplayPaper,
    "tell" => Murmur.Agents.TellAction,
  }

  def resolve(tool_ids), do: Enum.map(tool_ids, &Map.fetch!(@tools, &1))
  def list_available, do: Map.keys(@tools)
end
```

This follows the same pattern as the agent catalog — start with an explicit map, evolve to auto-discovery later if needed.

### Runtime system prompt injection (investigated)

The `use Jido.AI.Agent` macro compiles `system_prompt` into the strategy's `Config` struct at compile time. For user-defined agents, the system prompt must vary per agent instance. Three mechanisms exist:

#### Option 1: Per-request `system_prompt` in `ask/3` — NOT SUPPORTED

`ask/3` accepts `:tool_context`, `:tools`, `:allowed_tools`, `:request_transformer`, `:req_http_options`, and `:llm_opts`. **It does not accept `:system_prompt`.** The system prompt is not part of the request signal payload — it lives in the strategy's config, set at compile time. This option is off the table without upstream Jido changes.

Per-request **`:tools` override IS supported** though — `ask/3` accepts a `:tools` option that replaces the module's compiled tools for that request via `ToolSelection.resolve/3`. This is good news for user-defined agents: tool selection can vary per-request without a custom module.

#### Option 2: Request transformer (MessageInjector) — FUNCTIONAL BUT NOT IDEAL

The `RequestTransformer` callback receives the full `request.messages` list and can return `%{messages: [...]}` to replace it entirely. The current `MessageInjector` already does this — it appends team instructions to the system prompt and injects pending messages.

It _could_ also inject a custom system prompt by replacing the first `:system` message. However, this conflates unrelated concerns:

- **Team instructions** — dynamic per-turn context about the workspace roster. Legitimately belongs in a request transformer because it changes every turn.
- **Pending message draining** — inter-agent communication buffering. Legitimately per-turn.
- **System prompt** — the agent's core identity. Does NOT change per turn. Setting it in a per-turn transformer means the agent's identity is re-evaluated on every LLM call, which is wasteful and architecturally misleading.

**Verdict:** Using `MessageInjector` for system prompt injection works but is not best practice. It mixes a one-time configuration concern (identity) with per-turn request shaping (roster, pending messages). If the `MessageInjector` grows further responsibilities, it becomes a grab-bag that's hard to test and reason about.

A cleaner path: keep `MessageInjector` focused on its two current per-turn jobs (team instructions + pending messages). Handle system prompt via Option 3.

#### Option 3: `ai.react.set_system_prompt` signal — RECOMMENDED

Jido's ReAct strategy has a built-in action `ai.react.set_system_prompt` that **persistently updates** the agent's system prompt at runtime. It modifies `config.system_prompt`, the base `context.system_prompt`, and the active `run_context.system_prompt` all at once.

The flow for a user-defined agent would be:

```elixir
# 1. Start the generic CustomAgent (has a placeholder/empty system prompt)
{:ok, pid} = Murmur.Jido.start_agent(CustomAgent, id: session.id)

# 2. Immediately set the user-defined system prompt via signal
signal = Jido.Signal.new!(%{
  type: "ai.react.set_system_prompt",
  data: %{system_prompt: definition.system_prompt}
})
Jido.AgentServer.cast(pid, signal)

# 3. Now ask — the agent uses the custom prompt persistently
CustomAgent.ask(pid, content,
  tool_context: tool_ctx,
  tools: resolved_tool_modules  # per-request tool override is supported
)
```

**Why this is the right approach:**

| Concern | Mechanism | Frequency |
|---------|-----------|-----------|
| Agent identity (system prompt) | `set_system_prompt` signal | Once at startup |
| Per-request tools | `ask/3` `:tools` option | Per request |
| Team roster context | `MessageInjector` (request transformer) | Per LLM turn |
| Pending message drain | `MessageInjector` (request transformer) | Per LLM turn |

Each concern uses the mechanism that matches its lifecycle:
- **Startup-time config** → signals that persist in agent state
- **Per-request overrides** → `ask/3` options
- **Per-turn shaping** → request transformer

This keeps `MessageInjector` focused and avoids it becoming a god-object for all runtime customization.

#### Sketch: agent-state approach (Option 3 in practice)

```elixir
defmodule Murmur.Agents.Profiles.CustomAgent do
  @moduledoc "Generic data-driven agent for user-defined configurations."

  use Jido.AI.Agent,
    name: "custom_agent",
    description: "User-configured agent",
    tools: [Murmur.Agents.TellAction],  # base tools always available
    plugins: [Murmur.Agents.StreamingPlugin, Murmur.Agents.ArtifactPlugin],
    request_transformer: Murmur.Agents.MessageInjector,
    system_prompt: "You are a helpful AI assistant."  # fallback, always overridden
end
```

Lifecycle helper in the workspace or runner layer:

```elixir
defmodule Murmur.Agents.CustomSetup do
  @moduledoc "Configures a CustomAgent instance from a database agent definition."

  alias Murmur.Agents.Profiles.CustomAgent
  alias Murmur.Agents.ToolRegistry

  @doc """
  Starts a CustomAgent and configures it with the user-defined system prompt.
  Returns {:ok, pid} or {:error, reason}.
  """
  def start_custom_agent(session, definition) do
    with {:ok, pid} <- Murmur.Jido.start_agent(CustomAgent, id: session.id) do
      configure_system_prompt(pid, definition.system_prompt)
      {:ok, pid}
    end
  end

  defp configure_system_prompt(pid, system_prompt) when is_binary(system_prompt) do
    signal = Jido.Signal.new!(%{
      type: "ai.react.set_system_prompt",
      data: %{system_prompt: system_prompt}
    })
    Jido.AgentServer.cast(pid, signal)
  end

  @doc """
  Sends a message to a custom agent with the user-defined tool set.
  """
  def ask(pid, content, definition, tool_ctx) do
    tools = ToolRegistry.resolve(definition.tool_ids)
    CustomAgent.ask(pid, content, tool_context: tool_ctx, tools: tools)
  end
end
```

The `Runner` module would branch on whether the profile is built-in or custom:

```elixir
# In Runner.process_batch/2 (simplified):
defp process_batch(session, content) do
  pid = Murmur.Jido.whereis(session.id) || raise "agent gone"
  tool_ctx = %{workspace_id: session.workspace_id, sender_name: session.display_name}

  case Catalog.profile_type(session.agent_profile_id) do
    :built_in ->
      agent_module = Catalog.agent_module(session.agent_profile_id)
      llm_adapter().ask(agent_module, pid, content, tool_ctx)

    :custom ->
      definition = Catalog.get_custom_definition!(session.agent_profile_id)
      Murmur.Agents.CustomSetup.ask(pid, content, definition, tool_ctx)
  end
end
```

This keeps the existing flow intact for built-in agents and only adds the custom path when user-defined agents are enabled.
