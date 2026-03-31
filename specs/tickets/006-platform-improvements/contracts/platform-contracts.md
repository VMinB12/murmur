# Contract: PubSub Topics & Config Validation

**Scope**: jido_murmur, jido_tasks platform layer

## Module: `JidoMurmur.Topics`

All PubSub topic construction MUST use these functions:

```elixir
@spec agent_artifacts(workspace_id :: String.t(), session_id :: String.t()) :: String.t()
@spec agent_stream(workspace_id :: String.t(), session_id :: String.t()) :: String.t()
@spec agent_messages(workspace_id :: String.t(), session_id :: String.t()) :: String.t()
@spec workspace_tasks(workspace_id :: String.t()) :: String.t()
@spec workspace(workspace_id :: String.t()) :: String.t()
```

**Format**: `"workspace:{workspace_id}:{scope}:{entity_id}:{channel}"`

**Constraint**: No inline topic strings allowed anywhere in the codebase. `grep` for PubSub.broadcast/subscribe calls must only show `Topics.` function calls as topic arguments.

---

## Module: `JidoMurmur.Config`

```elixir
@spec validate!() :: :ok | no_return()
```

Called from `JidoMurmur.Supervisor.init/1`. Checks for required config keys. Raises with specific missing key names and remediation instructions on failure.

---

## Module: `JidoTasks.Config`

```elixir
@spec validate!() :: :ok | no_return()
```

Same pattern as JidoMurmur.Config. Checks `:repo` and `:pubsub` keys.

---

## Behaviour: `JidoMurmur.AgentProfile`

```elixir
@callback name() :: String.t()
@callback description() :: String.t()
@callback system_prompt() :: String.t()
@callback tools() :: [module()]
@callback plugins() :: [module()]
@callback opts() :: keyword()
```

Profile modules add `@behaviour JidoMurmur.AgentProfile` to gain compile-time validation.

---

## Telemetry Contract (`JidoTasks`)

All task context operations wrap in `:telemetry.span/3`:

```elixir
:telemetry.span([:jido_tasks, :task, :create], %{workspace_id: wid}, fn ->
  result = # ... actual creation
  {result, %{task_id: task.id, workspace_id: wid}}
end)
```

Events follow the standard span convention: `[:prefix, :stop]` includes `duration` measurement.
