# jido_tasks — Task Management

## Purpose

Task management system for Jido AI agents that enables collaborative task boards within workspaces. Provides Jido.Action tools for agents to create, update, and list tasks, with real-time PubSub broadcasting for UI synchronization.

## Public API

### Context API (JidoTasks.Tasks)

| Function | Purpose |
|----------|---------|
| `create_task/3` | Create new task with telemetry |
| `update_task/2` | Update status/title/description |
| `list_tasks/2` | List tasks, optionally filtered by status |
| `get_task!/1` | Fetch single task by ID |
| `task_stats/1` | Get task count breakdown by status |
| `delete_tasks_for_workspace/1` | Bulk delete all workspace tasks |
| `tasks_topic/1` | Get PubSub topic name for a workspace |

### Agent Tools (Jido.Action)

| Tool | Purpose | Parameters |
|------|---------|------------|
| `AddTask` | Create task + broadcast + notify assignee | `title` (req), `description`, `assignee` (req) |
| `UpdateTask` | Update task status/content | `task_id` (req), `status`, `title`, `description` |
| `ListTasks` | List tasks for agent consumption | `status` (optional filter) |

## Internal Architecture

### Data Flow

1. Agent calls `AddTask` → validates → inserts into DB → emits `TaskCreated` signal → broadcasts on PubSub → notifies assignee agent
2. Agent calls `UpdateTask` → validates → updates DB → emits `TaskUpdated` signal → broadcasts
3. Agent calls `ListTasks` → queries DB with optional status filter → formats for LLM

### Telemetry

All mutations wrapped with `:telemetry.span/3`:
- `[:jido_tasks, :task, :create]`
- `[:jido_tasks, :task, :update]`
- `[:jido_tasks, :task, :list]`

## Data Model

### Task Schema

```
jido_tasks
├── id: binary_id (PK)
├── title: string (required, max 200)
├── description: string (optional, max 2000)
├── assignee: string (required, immutable after creation)
├── status: enum [:todo, :in_progress, :done, :aborted] (default :todo)
├── created_by: string (required)
├── owner_id: string (optional)
├── metadata: map (default %{})
├── workspace_id: binary_id (FK → jido_murmur_workspaces, cascade delete)
├── index: (workspace_id)
├── index: (workspace_id, status)
└── timestamps (utc_datetime_usec)
```

### Signal Types

| Signal | Type | Subject |
|--------|------|---------|
| `TaskCreated` | `task.created` | `/workspaces/{wid}/tasks/{tid}` |
| `TaskUpdated` | `task.updated` | `/workspaces/{wid}/tasks/{tid}` |

## Dependencies

**Requires:** `jido ~> 2.0`, `jido_action ~> 2.0`, `jido_murmur` (umbrella), `ecto_sql ~> 3.13`, `postgrex`, `phoenix_pubsub ~> 2.0`, `jason ~> 1.2`

**Used by:** `murmur_demo` (all agent profiles include task tools)

## Configuration

```elixir
config :jido_tasks,
  repo: MyApp.Repo,
  pubsub: MyApp.PubSub
```
