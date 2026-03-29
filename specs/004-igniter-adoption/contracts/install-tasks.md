# Contract: Igniter Install Tasks

**Package**: All Murmur ecosystem packages  
**Igniter Version**: ~> 0.7

## Install Task Interface

All install tasks follow the same public contract:

```
mix {package_name}.install [--yes]
```

- Without `--yes`: shows diff preview, prompts for confirmation
- With `--yes`: applies changes without prompting

### `mix jido_murmur.install`

**Prerequisites**: None

**Actions**:
1. Generate migration: `create_workspaces`
2. Generate migration: `create_workspace_sessions`  
3. Generate migration: `create_messages`
4. Generate migration: `create_workspace_agents`
5. Add to `config/config.exs`:
   ```elixir
   config :jido_murmur,
     repo: {App}.Repo,
     pubsub: {App}.PubSub,
     jido_mod: {App}.Jido,
     otp_app: :{app}
   ```
6. Add `JidoMurmur.Supervisor` to supervision tree in `application.ex`

**Idempotency**: Skips existing migrations (by name match), skips config if `:jido_murmur` key exists.

---

### `mix jido_tasks.install`

**Prerequisites**: `:jido_murmur` must be configured

**Actions**:
1. If `:jido_murmur` not configured → compose `jido_murmur.install`
2. Generate migration: `create_jido_tasks`
3. Add to `config/config.exs`:
   ```elixir
   config :jido_tasks,
     repo: {App}.Repo,
     pubsub: {App}.PubSub
   ```

**Idempotency**: Skips if `:jido_tasks` config key exists.

---

### `mix jido_murmur_web.install`

**Prerequisites**: None

**Actions**:
1. Copy component files to `lib/{app}_web/components/jido_murmur/`
2. Inject import into `{app}_web.ex` html_helpers block

**Idempotency**: Skips files that already exist.

---

### `mix jido_artifacts.install`

**Prerequisites**: None

**Actions**:
1. Add to `config/config.exs`:
   ```elixir
   config :jido_artifacts,
     pubsub: {App}.PubSub
   ```

**Idempotency**: Skips if `:jido_artifacts` config key exists.

---

## Generator Interface

### `mix jido_murmur.gen.profile {Name}`

**Example**: `mix jido_murmur.gen.profile ResearchAssistant`

**Output**: `lib/{app}/agents/profiles/research_assistant.ex`

```elixir
defmodule {App}.Agents.Profiles.ResearchAssistant do
  use Jido.AI.Agent,
    name: "research_assistant",
    description: "A research assistant agent",
    model: :fast,
    tools: [JidoMurmur.TellAction],
    plugins: [JidoMurmur.StreamingPlugin, JidoArtifacts.ArtifactPlugin],
    system_prompt: "You are a helpful research assistant."

  def catalog_meta, do: %{color: "blue"}
end
```

---

## Fallback Behavior (No Igniter)

When Igniter is not in dependencies, all install tasks print:

```
** (Mix) This install task requires the Igniter package.

Add {:igniter, "~> 0.7"} to your deps in mix.exs, then re-run:

    mix jido_murmur.install

For manual setup instructions, see:
https://hexdocs.pm/jido_murmur/installation.html
```

## Dependency Declaration

Each package's mix.exs:
```elixir
{:igniter, "~> 0.7", optional: true, runtime: false}
```
