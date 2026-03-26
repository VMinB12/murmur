# Testing Agents and Actions (Jido 2.0)

Reference: https://jido.run/docs/guides/testing-agents-and-actions.md

## Core Principles

- **Agents are immutable structs.** Most tests need no processes, no mocks, and no async coordination.
- **Actions are pure functions.** Test them by calling `run/2` directly with a params map and a context map.
- **No LLM API calls in tests.** Tests should run entirely locally. No provider keys or network calls required.
- Call `cmd/2`, pattern match the result, and assert.

## Testing Actions in Isolation

Actions are pure functions. Test by calling `run/2` directly:

```elixir
# Success case
assert {:ok, %{count: 5}} =
  MyApp.IncrementAction.run(%{by: 5}, %{state: %{count: 0}})

# Error case
assert {:error, :division_by_zero} =
  MyApp.DivideAction.run(%{divisor: 0}, %{state: %{}})
```

## Testing Agent State Transitions

Create agents with `new/0` or `new/1`, exercise with `cmd/2`. Every call returns `{agent, directives}`:

```elixir
# Create with default state
agent = MyApp.CounterAgent.new()
assert agent.state.count == 0

# Create with custom state
agent = MyApp.CounterAgent.new(state: %{count: 10})
assert agent.state.count == 10

# Run actions and assert state changes
agent = MyApp.CounterAgent.new()
{agent, _directives} = MyApp.CounterAgent.cmd(agent, {MyApp.IncrementAction, %{by: 3}})
assert agent.state.count == 3

# State accumulates across sequential calls
{agent, _} = MyApp.CounterAgent.cmd(agent, {MyApp.IncrementAction, %{by: 5}})
assert agent.state.count == 8

# Pass custom IDs for deterministic assertions
agent = MyApp.CounterAgent.new(id: "test-counter-1")
assert agent.id == "test-counter-1"
```

## Asserting on Directives

`cmd/2` returns `{agent, directives}` — directives describe external effects:

```elixir
alias Jido.Agent.Directive

# Match directive types (e.g., Emit)
{_agent, directives} = MyAgent.cmd(agent, MyEmitAction)
assert [%Directive.Emit{signal: signal}] = directives
assert signal.type == "counter.updated"

# Match error directives (action fails validation or returns error)
{_agent, directives} = MyAgent.cmd(agent, MyBadAction)
assert [%Directive.Error{error: error}] = directives
assert error.class == :execution

# Empty directives — most actions produce none
{agent, directives} = MyAgent.cmd(agent, {MyAction, %{by: 1}})
assert directives == []
```

## Testing with the Runtime (AgentServer)

When you need to test signal routing, process lifecycle, or async behavior:

```elixir
# Start an agent server
{:ok, pid} = Jido.start_agent(runtime, MyApp.CounterAgent)

# Query state — agent struct lives at state.agent
{:ok, server_state} = Jido.AgentServer.state(pid)
assert server_state.agent.state.count == 0

# Send signals synchronously (call/2 — waits for processing)
signal = Jido.Signal.new!("counter.increment", %{by: 10}, source: "/test")
{:ok, agent} = Jido.AgentServer.call(pid, signal)
assert agent.state.count == 10

# Send signals asynchronously (cast/2 — returns :ok immediately)
:ok = Jido.AgentServer.cast(pid, signal)
# Query state after to verify processing
```

## Testing Signal Routes

Verify signal-to-action mapping without running the server:

```elixir
agent = MyApp.SignalCounterAgent.new()
routes = MyApp.SignalCounterAgent.signal_routes(%{agent: agent})
assert {"counter.increment", MyApp.IncrementAction} in routes
```

## Debug Mode in Tests

Record internal events in a ring buffer for verification:

```elixir
# Enable at startup
{:ok, pid} = Jido.start_agent(runtime, MyAgent, debug: true)

# Or enable at runtime
:ok = Jido.AgentServer.set_debug(pid, true)

# Retrieve recent events (each has :at, :type, :data)
{:ok, events} = Jido.AgentServer.recent_events(pid, limit: 10)
types = Enum.map(events, & &1.type)
assert :signal_received in types

# Returns error when debug is off
assert {:error, :debug_not_enabled} = Jido.AgentServer.recent_events(pid, limit: 5)
```

## ExUnit Patterns

### Test module skeleton

```elixir
defmodule MyApp.CounterAgentTest do
  use ExUnit.Case, async: true

  alias MyApp.{CounterAgent, IncrementAction}

  describe "state transitions" do
    test "increments count" do
      agent = CounterAgent.new()
      {agent, _} = CounterAgent.cmd(agent, {IncrementAction, %{by: 3}})
      assert agent.state.count == 3
    end
  end
end
```

### Runtime tests with setup

```elixir
defmodule MyApp.CounterServerTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, _} = Jido.start()
    {:ok, pid} = Jido.start_agent(
      Jido.default_instance(),
      MyApp.SignalCounterAgent
    )
    %{pid: pid}
  end

  test "processes signals", %{pid: pid} do
    signal = Jido.Signal.new!("counter.increment", %{by: 7}, source: "/test")
    {:ok, agent} = Jido.AgentServer.call(pid, signal)
    assert agent.state.count == 7
  end
end
```

## Key Testing Rules

1. **Never make real LLM/AI API calls in tests.** Mock or stub the AI layer.
2. **Test actions as pure functions** — call `run/2` directly with params and context.
3. **Test agents as state machines** — use `cmd/2` to drive transitions and assert on resulting state + directives.
4. **Test signal routing separately** — call `signal_routes/1` and assert mappings.
5. **Use `start_supervised!/1`** in ExUnit for processes that need cleanup between tests.
6. **Use `async: true`** for tests that don't need processes or shared state.
7. **Use debug mode** to verify signal processing without inspecting internal state.
