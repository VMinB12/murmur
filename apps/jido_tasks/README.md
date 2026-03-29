# JidoTasks

Task management tools for [Jido](https://github.com/agentjido/jido) agents. Provides `Jido.Action` implementations for creating, updating, and listing tasks — enabling agents to manage collaborative task boards.

## Installation

Add `jido_tasks` to your dependencies (requires `jido_murmur` for workspace schemas):

```elixir
def deps do
  [
    {:jido_murmur, "~> 0.1"},
    {:jido_tasks, "~> 0.1"}
  ]
end
```

Run the migration generator:

```bash
mix jido_tasks.install
mix ecto.migrate
```

## Configuration

```elixir
config :jido_tasks,
  repo: MyApp.Repo,
  pubsub: MyApp.PubSub
```

## Usage

Add task tools to an agent profile:

```elixir
defmodule MyApp.Agents.ProjectManager do
  use Jido.AI.Agent,
    name: "project_manager",
    description: "Manages project tasks",
    model: :capable,
    tools: [
      JidoMurmur.TellAction,
      JidoTasks.Tools.AddTask,
      JidoTasks.Tools.UpdateTask,
      JidoTasks.Tools.ListTasks
    ],
    plugins: [JidoMurmur.StreamingPlugin],
    system_prompt: "You are a project manager. Use task tools to track work."

  def catalog_meta, do: %{color: "green"}
end
```

The agent will automatically use these tools when users ask it to create, update, or list tasks.

## Tools

| Module | Action | Description |
|--------|--------|-------------|
| `JidoTasks.Tools.AddTask` | Create | Creates a new task in a workspace |
| `JidoTasks.Tools.UpdateTask` | Update | Updates task status, title, or description |
| `JidoTasks.Tools.ListTasks` | Read | Lists tasks with optional status filtering |

## Context API

For programmatic access outside of agent tools:

```elixir
alias JidoTasks.Tasks

# Create
{:ok, task} = Tasks.create_task(workspace_id, %{title: "Review PR", status: "todo"})

# Update
{:ok, task} = Tasks.update_task(task, %{status: "in_progress"})

# List
tasks = Tasks.list_tasks(workspace_id)
stats = Tasks.task_stats(workspace_id)
```

Task mutations broadcast PubSub events on `"workspace:#{workspace_id}"` for real-time UI updates.

## License

See LICENSE file.
