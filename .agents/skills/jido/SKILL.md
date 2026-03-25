---
name: jido
description: Use when working with Jido 2.0 agent framework — defining agents, actions, plugins, signals, strategies, and the AgentServer runtime. Use when building multi-agent or AI-powered features in Elixir.
---

# Jido 2.0 Agent Framework

Jido (自動 — "automatic") is a pure functional agent framework for building
autonomous multi-agent workflows in Elixir. It combines immutable agent data
structures with OTP runtime integration.

## Core Architecture

```
Agent (immutable struct) + Action (work to do)
    → Agent.cmd/2 (pure function)
    → {updated_agent, directives}
```

Key invariant: `cmd/2` is pure. The returned agent is always complete.
Side effects are described as **directives** and executed by the OTP runtime.

| Concept     | Purpose                                                |
| ----------- | ------------------------------------------------------ |
| Agent       | Immutable data struct holding state                    |
| Action      | Discrete unit of work (module with `run/2`)            |
| Instruction | Action + params + context (a "work order")             |
| Directive   | Description of external effect (emit, spawn, schedule) |
| Signal      | CloudEvents v1.0.2 message format                      |
| Strategy    | Execution pattern for `cmd/2` (Direct, FSM, custom)    |
| Plugin      | Composable capability (actions + state + routes)       |
| AgentServer | GenServer runtime that executes directives             |

## Defining an Agent

```elixir
defmodule MyApp.Agents.ResearchAgent do
  use Jido.Agent,
    name: "research_agent",
    description: "Researches topics using web search",
    category: "research",
    tags: ["ai", "search"],
    vsn: "1.0.0",
    schema: [
      status: [type: :atom, default: :idle],
      messages: [type: {:list, :map}, default: []]
    ],
    strategy: Jido.Agent.Strategy.Direct,
    plugins: [MyApp.Plugins.ChatPlugin],
    signal_routes: [
      {"chat.message", MyApp.Actions.ProcessMessage}
    ]
end
```

### Agent Creation

```elixir
agent = MyApp.Agents.ResearchAgent.new()
agent = MyApp.Agents.ResearchAgent.new(id: "agent-1", state: %{status: :ready})
```

### Agent Execution (Pure)

```elixir
{agent, directives} = MyApp.Agents.ResearchAgent.cmd(agent, MyAction)
{agent, directives} = MyApp.Agents.ResearchAgent.cmd(agent, {MyAction, %{param: value}})
{agent, directives} = MyApp.Agents.ResearchAgent.cmd(agent, [Action1, Action2])
```

### Agent State

```elixir
{:ok, agent} = MyApp.Agents.ResearchAgent.set(agent, %{status: :running})
{:ok, agent} = MyApp.Agents.ResearchAgent.validate(agent)
```

### Optional Callbacks

```elixir
@callback on_before_cmd(agent, action) :: {:ok, agent, action}
@callback on_after_cmd(agent, action, directives) :: {:ok, agent, directives}
@callback checkpoint(agent, ctx) :: {:ok, map()} | {:error, term()}
@callback restore(data, ctx) :: {:ok, agent} | {:error, term()}
```

## Defining Actions

Actions are the building blocks of agent behavior.

```elixir
defmodule MyApp.Actions.SearchWeb do
  use Jido.Action,
    name: "search_web",
    description: "Search the web for a query",
    schema: [
      query: [type: :string, required: true],
      max_results: [type: :integer, default: 5]
    ],
    output_schema: [
      results: [type: {:list, :map}, required: true]
    ]

  @impl true
  def run(params, context) do
    # params = validated input, context = execution context
    results = do_search(params.query, params.max_results)
    {:ok, %{results: results}}
  end
end
```

### Action Execution

```elixir
{:ok, result} = Jido.Exec.run(MyAction, %{query: "elixir"}, %{})
async_ref = Jido.Exec.run_async(MyAction, params, context)
result = Jido.Exec.await(async_ref)
```

### AI Tool Integration

Actions auto-convert to OpenAI function calling format:

```elixir
tool = MyApp.Actions.SearchWeb.to_tool()
# => %{"name" => "search_web", "parameters" => %{...}, ...}
```

### Action Metadata

```elixir
MyAction.name()           # "search_web"
MyAction.description()    # "Search the web..."
MyAction.schema()         # Input schema
MyAction.to_json()        # Full serialized metadata
```

## AgentServer (OTP Runtime)

The AgentServer is a GenServer that wraps an Agent and executes directives.

### Setup

```elixir
# 1. Create Jido supervisor module
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app
end

# 2. Add to supervision tree in application.ex
children = [
  # ... other children
  MyApp.Jido
]
```

### Starting Agents

```elixir
{:ok, pid} = MyApp.Jido.start_agent(MyAgent)
{:ok, pid} = MyApp.Jido.start_agent(MyAgent, id: "agent-1", initial_state: %{})
```

### Interacting with Agents

```elixir
# Send signal (sync)
{:ok, agent} = Jido.AgentServer.call(pid, signal, timeout_ms)

# Send signal (async — fire and forget)
:ok = Jido.AgentServer.cast(pid, signal)

# Get current state
{:ok, state} = Jido.AgentServer.state(pid)

# Get strategy snapshot (status, done?, result)
{:ok, snapshot} = Jido.AgentServer.snapshot(pid)

# Lookup by ID
pid = Jido.AgentServer.whereis(id)
pid = MyApp.Jido.whereis("agent-1")

# List all agents
agents = MyApp.Jido.list_agents()  # [{id, pid}, ...]

# Stop
:ok = Jido.AgentServer.stop(pid)
:ok = MyApp.Jido.stop_agent("agent-1")
```

### Signal Flow

```
Signal → AgentServer.call/cast
      → route_signal_to_action (via signal_routes)
      → Agent.cmd/2
      → {agent, directives}
      → Directive drain loop (executed by runtime)
```

### Completion Detection

Agents signal completion via state, not process death:

```elixir
# In agent logic
agent = put_in(agent.state.status, :completed)

# External poll
{:ok, state} = AgentServer.state(server)

# Or use Await
{:ok, %{status: :completed, result: answer}} =
  Jido.Await.completion(pid, 10_000)

# Wait for multiple
{:ok, results} = Jido.Await.all([pid1, pid2], 30_000)
{:ok, {winner, result}} = Jido.Await.any([pid1, pid2], 10_000)
```

## Signals (CloudEvents v1.0.2)

Signals are the universal message format.

```elixir
alias Jido.Signal

{:ok, signal} = Signal.new(
  "chat.message.received",           # type
  %{content: "hello", role: "user"}, # data
  source: "/workspace/123"           # attributes
)
```

### Signal Dispatch

```elixir
alias Jido.Signal.Dispatch

Dispatch.dispatch(signal, {:pubsub, topic: "events"})
Dispatch.dispatch(signal, [
  {:pubsub, topic: "events"},
  {:logger, level: :debug}
])
```

Adapters: `:pid`, `:pubsub`, `:bus`, `:http`, `:webhook`, `:logger`, `:noop`

## Directives (Effects)

Directives describe side effects. The AgentServer executes them.

```elixir
alias Jido.Agent.Directive

# Emit a signal
%Directive.Emit{signal: signal, dispatch: {:pubsub, topic: "events"}}

# Spawn a child process
%Directive.Spawn{mfa: {Mod, :func, [args]}, tag: :worker, restart: :temporary}

# Spawn a child agent
%Directive.SpawnAgent{agent: ChildAgent, id: "child-1", initial_state: %{}}

# Stop a child
%Directive.StopChild{tag: :worker, timeout: 5000}

# Schedule delayed work
%Directive.Schedule{delay_ms: 5000, message: :timeout}

# Execute instruction async, route result back
%Directive.RunInstruction{instruction: inst, result_action: :my_result_handler}

# Stop self
%Directive.Stop{}
```

## Plugins (Composable Capabilities)

```elixir
defmodule MyApp.Plugins.ChatPlugin do
  use Jido.Plugin,
    name: "chat",
    state_key: :chat,
    description: "Chat capabilities",
    actions: [MyApp.Actions.SendMessage],
    schema: Zoi.object(%{
      messages: Zoi.list(Zoi.any()) |> Zoi.default([]),
      model: Zoi.string() |> Zoi.default("gpt-4")
    }),
    signal_routes: [
      {"chat.send", MyApp.Actions.SendMessage}
    ]

  @impl Jido.Plugin
  def mount(_agent, _config) do
    {:ok, %{initialized_at: DateTime.utc_now()}}
  end
end
```

Plugin state lives under `agent.state[state_key]`.

## Strategies

Strategies control how `cmd/2` executes instructions.

```elixir
defmodule Jido.Agent.Strategy do
  @callback cmd(agent, instructions, context) :: {agent, directives}
  @callback init(agent, context) :: {agent, directives}
  @callback tick(agent, context) :: {agent, directives}
  @callback snapshot(agent, context) :: Strategy.Snapshot.t()
end
```

Snapshot struct:

```elixir
%Jido.Agent.Strategy.Snapshot{
  status: :idle | :running | :waiting | :success | :failure,
  done?: boolean(),
  result: map() | nil,
  details: %{}
}
```

Default strategy: `Jido.Agent.Strategy.Direct` — executes instructions immediately.

## Instructions & Plans

### Instructions (Work Orders)

```elixir
# Various creation formats
MyAction                                    # bare module
{MyAction, %{param: "value"}}              # with params
%Jido.Instruction{action: MyAction, params: %{}, context: %{}}
Jido.Instruction.new!(%{action: MyAction, params: %{}})
```

### Plans (DAGs)

```elixir
plan = Jido.Plan.new()
  |> Jido.Plan.add(:fetch, FetchAction)
  |> Jido.Plan.add(:validate, ValidateAction, depends_on: :fetch)
  |> Jido.Plan.add(:save, SaveAction, depends_on: :validate)

# Parallel fan-out
plan = Jido.Plan.new()
  |> Jido.Plan.add(:fetch_a, FetchA)
  |> Jido.Plan.add(:fetch_b, FetchB)
  |> Jido.Plan.add(:merge, Merge, depends_on: [:fetch_a, :fetch_b])
```

## Memory System

Agents have versioned memory under `agent.state.__memory__`:

```elixir
%Jido.Memory{
  id: "mem_abc",
  rev: 0,
  spaces: %{
    world: %Space{data: %{"key" => "value"}, rev: 0},
    tasks: %Space{data: [%{id: "t1", status: :pending}], rev: 0}
  }
}
```

## Common Patterns

### Pattern: Agent with PubSub Broadcasting

When an agent needs to broadcast state changes (e.g., to a LiveView):

1. Define a signal route that maps incoming signals to actions
2. In the action's `run/2`, return results
3. In `on_after_cmd/3`, emit a `Directive.Emit` with PubSub dispatch
4. The LiveView subscribes to the PubSub topic and handles messages

### Pattern: Inter-Agent Communication

Agents communicate via signals, not direct process messaging:

1. Agent A's action returns a `Directive.Emit` targeting Agent B's topic
2. Or use `Jido.AgentServer.cast(target_pid, signal)` from within an action
3. Target agent routes the signal to the appropriate action via `signal_routes`

### Pattern: Pending Message Injection

For injecting messages into a busy agent (e.g., "tell" tool):

1. Add `pending_injections` to agent state schema
2. When busy, append incoming messages to pending list
3. Before each LLM call, drain the queue via `GenServer.call(:get_and_clear_injections)`
4. Merge drained messages into the active conversation history

---

## Jido.AI — AI Agent Integration (jido_ai 2.0)

`jido_ai` extends Jido with LLM-powered agents, ReAct reasoning, streaming,
and tool calling. It depends on `req_llm` for HTTP transport to LLM providers.

### Defining an AI Agent

Use `Jido.AI.Agent` (not plain `Jido.Agent`) for agents that call LLMs:

```elixir
defmodule MyApp.Agents.ResearchAgent do
  use Jido.AI.Agent,
    name: "research_agent",
    model: :fast,                     # model alias (see config below)
    tools: [MyApp.Actions.SearchWeb], # Jido.Action modules auto-convert to LLM tools
    max_iterations: 8,
    system_prompt: "You are a research assistant. Use tools when needed.",
    llm_opts: [reasoning_effort: :high]
end
```

Key options: `model`, `tools`, `system_prompt`, `max_iterations`, `effect_policy`,
`request_transformer`, `llm_opts`.

### ask / await (Async Request + Correlation)

```elixir
{:ok, pid} = Jido.AgentServer.start(agent: MyApp.Agents.ResearchAgent)

# Async: returns a request handle immediately
{:ok, req} = MyApp.Agents.ResearchAgent.ask(pid, "Search for Elixir OTP patterns")
{:ok, result} = MyApp.Agents.ResearchAgent.await(req, timeout: 15_000)

# Per-request overrides
{:ok, req2} = MyApp.Agents.ResearchAgent.ask(pid, "Follow up question",
  allowed_tools: ["search_web"],
  tool_context: %{tenant_id: "acme"},
  llm_opts: [reasoning_effort: :medium]
)
```

### Standalone ReAct Runtime (Streaming)

For streaming events without a long-lived agent process:

```elixir
alias Jido.AI.Reasoning.ReAct

config = %{
  model: :fast,
  system_prompt: "Solve accurately. Use tools for arithmetic.",
  tools: [MyApp.Actions.AddNumbers],
  streaming: true,    # default
  max_iterations: 10  # default
}

# Lazy stream of ReAct.Event structs
events = ReAct.stream("What is 19 + 23?", config)
events |> Stream.each(fn event ->
  IO.puts("[#{event.kind}] #{inspect(event.data)}")
end) |> Stream.run()

# Or collect into a result map
result = ReAct.stream("What is 19 + 23?", config) |> ReAct.collect_stream()
# => %{result: "42", termination_reason: :final_answer, usage: %{...}, trace: [...]}

# Run to completion (no streaming needed)
result = ReAct.run("What is 19 + 23?", config)
```

Event kinds: `:request_started`, `:llm_started`, `:llm_delta` (streaming token),
`:llm_completed`, `:tool_started`, `:tool_completed`, `:checkpoint`,
`:request_completed`, `:request_failed`, `:request_cancelled`.

### LLM Facade (One-Shot Generation)

For simple one-off LLM calls without agent processes:

```elixir
# Text generation
{:ok, text} = Jido.AI.ask("Summarize OTP in one sentence.", model: :fast)
{:ok, response} = Jido.AI.generate_text("Summarize OTP.", model: :fast, temperature: 0.3)

# Structured output
{:ok, result} = Jido.AI.generate_object("Extract priority from: urgent bug", schema, model: :thinking)

# Streaming (thin pass-through to ReqLLM)
{:ok, stream_response} = Jido.AI.stream_text("Write release notes", model: :fast)
```

### Configuration: Model Aliases & API Keys

```elixir
# config/config.exs
config :jido_ai,
  model_aliases: %{
    fast: "openai:gpt-4o-mini",
    capable: "openai:gpt-4o",
    thinking: "openai:o3-mini"
  },
  llm_defaults: %{
    text: %{model: :fast, temperature: 0.2, max_tokens: 1024, timeout: 30_000},
    stream: %{model: :fast, temperature: 0.2, max_tokens: 1024, timeout: 30_000}
  }

# config/runtime.exs
config :req_llm,
  openai_api_key: System.get_env("OPENAI_API_KEY")
  # anthropic_api_key: System.get_env("ANTHROPIC_API_KEY")
```

Built-in aliases: `:fast`, `:capable`, `:thinking`, `:reasoning`, `:planning`,
`:image`, `:embedding`. Override them in `model_aliases`.

### Tool Actions for AI

Actions work as LLM tools automatically. Define with `Zoi` schemas:

```elixir
defmodule MyApp.Actions.AddNumbers do
  use Jido.Action,
    name: "add_numbers",
    description: "Add two numbers.",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  @impl true
  def run(%{a: a, b: b}, _context), do: {:ok, %{sum: a + b}}
end
```

Dynamic tool registration on a running agent:

```elixir
{:ok, _agent} = Jido.AI.register_tool(agent_pid, MyApp.Actions.AddNumbers)
{:ok, true}   = Jido.AI.has_tool?(agent_pid, "add_numbers")
```

Runtime system prompt update:

```elixir
{:ok, _agent} = Jido.AI.set_system_prompt(pid, "You are a concise support specialist.")
```

### Conversation Context Restore

Persist and restore conversation history across agent restarts:

```elixir
# Save: get snapshot
{:ok, snapshot} = Jido.AgentServer.snapshot(pid)
saved_messages = snapshot.details.conversation

# Restore: rebuild context and start with it
context =
  Jido.AI.Context.new(system_prompt: saved_system_prompt)
  |> Jido.AI.Context.append_messages(conversation_messages)

Jido.AgentServer.start_link(agent: MyAgent, initial_state: %{context: context})
```

### ReAct Defaults

| Setting          | Default  |
| ---------------- | -------- |
| model            | `:fast`  |
| streaming        | `true`   |
| max_iterations   | `10`     |
| max_tokens       | `4_096`  |
| temperature      | `0.2`    |
| tool_choice      | `:auto`  |
| tool_timeout_ms  | `15_000` |
| tool_max_retries | `1`      |
| tool_concurrency | `4`      |

## Key Gotchas

- `Agent.cmd/2` is **pure** — never do side effects inside it
- Directives are the **only** mechanism for side effects
- Agent state uses **NimbleOptions** or **Zoi** schemas — pick one per agent
- `AgentServer.state/1` returns the full server state map, access agent via `state.agent`
- Completion is via **state mutation** (e.g., `status: :completed`), not process exit
- `signal_routes` patterns support wildcards: `"chat.*"` matches `"chat.send"`, `"chat.history"`
- Plugin state lives under `agent.state[plugin.state_key]` — don't collide keys
- `Jido.Await` helpers require the agent state to have a `status` field at the expected path
