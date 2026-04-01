# Shared Task Board: Design & Implementation

## Problem

Agents in a Murmur workspace have no mechanism to coordinate work. Users can
instruct agents via chat, and agents can send each other messages with `tell`,
but there is no structured way to track what needs to be done, who is doing it,
and what the current status is.

We need a **shared task board** — a kanban-style artifact visible to all agents
and humans in the workspace. Agents must be able to create, update, and query
tasks through tool actions, and users must be able to interact with the board
directly in the UI.

## Requirements

### Data model

Each task has:

| Field | Type | Notes |
|-------|------|-------|
| `id` | binary_id | Auto-generated, PK |
| `title` | string | Required, max 200 chars |
| `description` | string | Optional, max 2000 chars |
| `assignee` | string | Required — display name of an agent or `"human"` |
| `status` | enum | `todo` \| `in_progress` \| `done` \| `aborted` |
| `created_by` | string | Display name of creator (agent or `"human"`) |
| `workspace_id` | FK → workspaces | Scoping |
| `inserted_at` | utc_datetime_usec | |
| `updated_at` | utc_datetime_usec | |

Tasks are **workspace-scoped** — all agents and users in a workspace share the
same board. This is the first **shared artifact** in Murmur, distinct from the
existing per-session artifacts (papers, PDFs).

### Agent tools

Three tool actions available to every agent:

1. **`add_task`** — Create a new task. Params: `title`, `description`
   (optional), `assignee`. The creator is the calling agent.

2. **`update_task`** — Change a task's `status`, `title`, or `description`.
   Params: `task_id`, plus any of `status`, `title`, `description`. Agents
   **cannot** change the assignee (prevents reassignment loops; requires human
   oversight or a separate escalation mechanism).

3. **`list_tasks`** — List current tasks. Params: `status` (optional filter).
   Returns a formatted list the LLM can reason about.

### Notification on assignment

When a task is created and assigned to an agent, that agent must receive a
notification message. The message delivery must:

- Interrupt an idle agent (start a new react loop)
- Be queued for a busy agent (injected on next iteration)
- Be visible in the agent's chat column

This is identical to the `tell` tool's delivery mechanism: PubSub broadcast
for LiveView display + `Runner.send_message` for agent delivery via
`PendingQueue`.

### User interaction

Users must be able to:

- View the kanban board in the artifact panel
- Drag tasks between status columns (or use buttons)
- Click a task to view/edit its details
- Create new tasks from the UI
- Mark tasks as done/aborted

### Persistence

Tasks must survive:

- Page refresh (LiveView remount)
- Server restart (BEAM restart)

This rules out in-process storage (agent state, ETS, GenServer). Tasks must
be persisted to PostgreSQL.

---

## Architecture Decision: Why a Dedicated DB Table

The existing artifact system stores data in agent state (per-session, persisted
via Jido checkpoints). This works for single-agent artifacts like paper lists.
Tasks are fundamentally different:

| Property | Per-agent artifacts | Shared tasks |
|----------|-------------------|--------------|
| Ownership | Single agent session | Workspace (all agents) |
| Scope | Session | Workspace |
| Writers | One agent | Any agent + human |
| Readers | One LiveView session | All LiveView sessions |
| Lifecycle | Tied to agent session | Tied to workspace |

Storing tasks in a single agent's state doesn't work because:

1. **No single owner** — Any agent can create/update tasks. Putting them in one
   agent's checkpoint means other agents can't write without cross-agent state
   mutation, which violates Jido's isolation model.

2. **Checkpoint timing** — Agent state only persists on `hibernate` (end of LLM
   turn). A task created mid-turn by one agent wouldn't be visible to others
   until that turn completes.

3. **Cleanup semantics** — Removing an agent would delete its checkpoint,
   taking all tasks with it. Tasks should outlive individual agent sessions.

**Decision: Dedicated `tasks` table in PostgreSQL**, with an Ecto schema and
context module. This is a clean, well-understood approach that:

- Provides immediate persistence on every write
- Supports concurrent reads/writes from any agent or the LiveView
- Has clear lifecycle tied to workspace deletion
- Works with existing Ecto/Repo infrastructure

This aligns with the "workspace-scoped DB table" direction outlined in
`artifact-persistence.md` for Phase 3 shared artifacts.

---

## Detailed Design

### 1. Database layer

#### Migration

```elixir
create table(:tasks, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
    null: false
  add :title, :string, null: false
  add :description, :text
  add :assignee, :string, null: false
  add :status, :string, null: false, default: "todo"
  add :created_by, :string, null: false

  timestamps(type: :utc_datetime_usec)
end

create index(:tasks, [:workspace_id])
create index(:tasks, [:workspace_id, :status])
```

No unique constraints beyond the PK — multiple tasks can share titles,
assignees, etc.

#### Ecto schema: `Murmur.Tasks.Task`

```elixir
defmodule Murmur.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tasks" do
    field :title, :string
    field :description, :string
    field :assignee, :string
    field :status, Ecto.Enum, values: [:todo, :in_progress, :done, :aborted], default: :todo
    field :created_by, :string

    belongs_to :workspace, Murmur.Workspaces.Workspace

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :description, :assignee, :status])
    |> validate_required([:title, :assignee])
    |> validate_length(:title, max: 200)
    |> validate_length(:description, max: 2000)
    |> validate_inclusion(:status, [:todo, :in_progress, :done, :aborted])
  end

  def update_changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :description, :status])
    |> validate_length(:title, max: 200)
    |> validate_length(:description, max: 2000)
    |> validate_inclusion(:status, [:todo, :in_progress, :done, :aborted])
  end
end
```

#### Context module: `Murmur.Tasks`

```elixir
defmodule Murmur.Tasks do
  import Ecto.Query
  alias Murmur.Repo
  alias Murmur.Tasks.Task

  def list_tasks(workspace_id, opts \\ []) do
    query = from t in Task, where: t.workspace_id == ^workspace_id, order_by: [asc: t.inserted_at]

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> where(query, [t], t.status == ^status)
      end

    Repo.all(query)
  end

  def get_task!(id), do: Repo.get!(Task, id)

  def create_task(workspace_id, attrs, created_by) do
    %Task{workspace_id: workspace_id, created_by: created_by}
    |> Task.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_task(%Task{} = task, attrs) do
    task
    |> Task.update_changeset(attrs)
    |> Repo.update()
  end

  def delete_tasks_for_workspace(workspace_id) do
    from(t in Task, where: t.workspace_id == ^workspace_id)
    |> Repo.delete_all()
  end
end
```

### 2. Real-time broadcast

Tasks are a workspace-scoped resource. All participants (agents + LiveView)
need to see updates in real time.

**PubSub topic:** `workspace:<workspace_id>:tasks`

Every task mutation (create, update) broadcasts to this topic:

```elixir
# After successful DB write
Phoenix.PubSub.broadcast(
  Murmur.PubSub,
  "workspace:#{workspace_id}:tasks",
  {:task_created, task}
  # or {:task_updated, task}
)
```

The LiveView subscribes to this topic on mount and updates `@tasks` (a stream,
since tasks are a collection).

### 3. Agent tool actions

#### `Murmur.Agents.Tools.AddTask`

```elixir
defmodule Murmur.Agents.Tools.AddTask do
  use Jido.Action,
    name: "add_task",
    description: """
    Create a new task on the shared workspace task board.
    Assign it to yourself, another agent, or "human".
    The assigned agent will be notified immediately.
    """,
    schema: [
      title: [type: :string, required: true, doc: "Task title (max 200 chars)"],
      description: [type: :string, doc: "Task description (max 2000 chars)"],
      assignee: [type: :string, required: true, doc: "Display name of the agent or 'human'"]
    ]

  def run(params, ctx) do
    workspace_id = ctx[:workspace_id]
    sender_name = ctx[:sender_name]

    attrs = %{
      title: params.title,
      description: params[:description],
      assignee: params.assignee,
      status: :todo
    }

    case Tasks.create_task(workspace_id, attrs, sender_name) do
      {:ok, task} ->
        broadcast_task_created(workspace_id, task)
        notify_assignee(workspace_id, task, sender_name)
        {:ok, %{result: "Task created: \"#{task.title}\" assigned to #{task.assignee}"}}

      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end
end
```

**Key point:** `notify_assignee/3` uses the same delivery path as `tell` —
finds the target agent session, broadcasts a `{:new_message, ...}` for the
LiveView, and calls `Runner.send_message` to enqueue the notification in the
agent's `PendingQueue`. If the assignee is `"human"`, no agent notification
is sent (humans see the board update via PubSub).

#### `Murmur.Agents.Tools.UpdateTask`

```elixir
defmodule Murmur.Agents.Tools.UpdateTask do
  use Jido.Action,
    name: "update_task",
    description: """
    Update an existing task on the workspace task board.
    You can change the status, title, or description.
    You cannot change the assignee.
    """,
    schema: [
      task_id: [type: :string, required: true, doc: "The task ID to update"],
      status: [type: :string, doc: "New status: todo, in_progress, done, or aborted"],
      title: [type: :string, doc: "New title"],
      description: [type: :string, doc: "New description"]
    ]

  def run(params, ctx) do
    workspace_id = ctx[:workspace_id]
    task = Tasks.get_task!(params.task_id)

    # Verify the task belongs to this workspace
    if task.workspace_id != workspace_id do
      {:error, "Task not found in this workspace"}
    else
      attrs =
        %{}
        |> maybe_put(:status, params[:status])
        |> maybe_put(:title, params[:title])
        |> maybe_put(:description, params[:description])

      case Tasks.update_task(task, attrs) do
        {:ok, updated} ->
          broadcast_task_updated(workspace_id, updated)
          {:ok, %{result: "Task updated: \"#{updated.title}\" → #{updated.status}"}}

        {:error, changeset} ->
          {:error, format_errors(changeset)}
      end
    end
  end
end
```

#### `Murmur.Agents.Tools.ListTasks`

```elixir
defmodule Murmur.Agents.Tools.ListTasks do
  use Jido.Action,
    name: "list_tasks",
    description: "List tasks from the workspace task board, optionally filtered by status.",
    schema: [
      status: [type: :string, doc: "Filter by status: todo, in_progress, done, aborted"]
    ]

  def run(params, ctx) do
    workspace_id = ctx[:workspace_id]
    opts = if params[:status], do: [status: String.to_existing_atom(params.status)], else: []
    tasks = Tasks.list_tasks(workspace_id, opts)

    formatted =
      tasks
      |> Enum.map(fn t ->
        "- [#{t.status}] \"#{t.title}\" (assigned to: #{t.assignee}, id: #{t.id})"
      end)
      |> Enum.join("\n")

    summary =
      if formatted == "" do
        "No tasks found."
      else
        "#{length(tasks)} task(s):\n#{formatted}"
      end

    {:ok, %{result: summary}}
  end
end
```

### 4. Notification on assignment

When `AddTask` creates a task assigned to an agent, it must deliver a
notification. The mechanism mirrors `TellAction.deliver_message`:

```elixir
defp notify_assignee(workspace_id, task, sender_name) do
  if task.assignee == "human", do: :noop, else: do_notify(workspace_id, task, sender_name)
end

defp do_notify(workspace_id, task, sender_name) do
  case Workspaces.find_agent_session_by_name(workspace_id, task.assignee) do
    nil -> :ok  # Assignee not found — might be a typo
    target_session ->
      message = "[#{sender_name}] assigned you a task: \"#{task.title}\""
      message = if task.description, do: message <> "\nDescription: #{task.description}", else: message
      message = message <> "\nTask ID: #{task.id}"

      # Broadcast for LiveView display (same pattern as TellAction)
      topic = "workspace:#{workspace_id}:agent:#{target_session.id}"
      inter_msg = %{
        id: Murmur.ID.generate!(),
        role: "user",
        content: message,
        sender_name: sender_name
      }
      Phoenix.PubSub.broadcast(Murmur.PubSub, topic, {:new_message, target_session.id, inter_msg})

      # Enqueue for agent processing (starts react loop if idle)
      Runner.send_message(target_session, message)
  end
end
```

This guarantees:

- **Idle agent**: `PendingQueue.enqueue` + `Runner.maybe_start_loop` → new
  react loop starts, agent processes the notification
- **Busy agent**: `PendingQueue.enqueue` → `MessageInjector` drains it on the
  next LLM call within the current react loop
- **LiveView**: `:new_message` broadcast shows the notification in the agent's
  chat column immediately

### 5. LiveView integration

#### State management

```elixir
# In mount/3
tasks = Tasks.list_tasks(workspace_id)

socket
|> stream(:tasks, tasks)
|> assign(:tasks_empty?, tasks == [])
```

Subscribe to the tasks topic:

```elixir
if connected?(socket) do
  Phoenix.PubSub.subscribe(Murmur.PubSub, "workspace:#{workspace_id}:tasks")
end
```

Handle PubSub broadcasts:

```elixir
def handle_info({:task_created, task}, socket) do
  {:noreply,
   socket
   |> stream_insert(:tasks, task)
   |> assign(:tasks_empty?, false)}
end

def handle_info({:task_updated, task}, socket) do
  {:noreply, stream_insert(socket, :tasks, task)}
end
```

#### User interactions via LiveView events

```elixir
# User creates a task from UI
def handle_event("create_task", %{"task" => params}, socket) do
  workspace_id = socket.assigns.workspace.id
  attrs = %{title: params["title"], description: params["description"],
            assignee: params["assignee"], status: :todo}

  case Tasks.create_task(workspace_id, attrs, "human") do
    {:ok, task} ->
      broadcast_task_created(workspace_id, task)
      notify_assignee(workspace_id, task, "You (human)")
      {:noreply, socket}  # PubSub handler will update the stream

    {:error, changeset} ->
      {:noreply, put_flash(socket, :error, "Failed to create task")}
  end
end

# User drags task to a new column (or clicks status button)
def handle_event("update_task_status", %{"task_id" => id, "status" => status}, socket) do
  task = Tasks.get_task!(id)
  status_atom = String.to_existing_atom(status)

  case Tasks.update_task(task, %{status: status_atom}) do
    {:ok, updated} ->
      broadcast_task_updated(socket.assigns.workspace.id, updated)
      {:noreply, socket}

    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Failed to update task")}
  end
end
```

### 6. UI design: Kanban board

The task board renders as a new artifact type in the artifact panel. Since it's
workspace-scoped (not session-scoped), it gets special treatment in the panel.

**Four columns:** Todo → In Progress → Done → Aborted

Each task card shows:
- Title (bold)
- Assignee badge with agent color
- Description excerpt (truncated)
- Created-by attribution
- Timestamp

**User interactions:**
- Click `+ Add Task` button at top of each column (or a global add button)
- Click task card to expand details / edit
- Status change buttons on each card (or drag between columns via JS hook)
- Simple form modal for creating/editing tasks

#### Component structure

```
lib/murmur_web/components/artifacts/
  task_board.ex          # Kanban board component (badge + detail)
```

#### Integration with artifact panel

The task board is **always present** as a tab in the artifact panel (it doesn't
require an agent to emit it). Two approaches:

**Option 1: Virtual artifact tab.** The artifact panel's tab list includes a
hard-coded "Task Board" entry alongside per-session artifacts. Selecting it
renders the kanban component driven by `@tasks` (the stream).

**Option 2: Workspace-scoped artifact.** Extend the artifact system to support
workspace-level artifacts (no session_id). The task board is the first instance.

**Recommendation: Option 1 for now.** A hard-coded tab is simpler and avoids
changes to the artifact dispatcher. The task board is special enough (shared,
DB-backed, user-interactive) to warrant distinct treatment. If more workspace-
scoped artifacts follow, Option 2 can be introduced then.

### 7. Agent profile registration

All agents need the task tools. Two approaches:

**Option A: Add to every profile.** Each agent profile lists the three task
tools in its `tools:` list.

**Option B: Global tools.** Extend the agent profile system to support
workspace-scoped tools that are automatically available to all agents.

**Recommendation: Option A.** Adding three tools to each profile is trivial
and explicit. A global tools mechanism is premature.

The system prompt for each agent should be extended (via `TeamInstructions`)
to describe the task board and available actions.

---

## Alternatives Considered

### Store tasks in agent state (per artifact persistence Option A)

As detailed in `artifact-persistence.md`, storing shared data in a single
agent's state doesn't work because there's no single owner. Even if we picked
one agent as the "task board owner," other agents would need a cross-agent
write path, and the data would be lost if that agent is removed.

### Store tasks as thread entries

Could append task operations as special thread entries. But tasks need cross-
session visibility (all agents see all tasks), and thread entries are
per-session. Reconstructing the current task state from scattered thread entries
across all sessions is fragile and expensive.

### Shared GenServer without DB backing

A workspace-scoped GenServer could hold all tasks in memory and broadcast
changes via PubSub. This handles real-time well but doesn't survive server
restart without a persistence layer. Adding a DB write to the GenServer is
essentially the recommended approach but with an extra process to manage.

**Verdict:** The DB-first approach is simpler. We don't need a GenServer's
in-process state because the LiveView stream already serves as the in-memory
read cache, and Ecto queries are fast enough for the expected task volume
(tens to low hundreds per workspace).

### CRDT-based shared state

Excessive for structured task management. CRDTs shine for free-form text
editing where conflicts are common. Task operations are discrete and can be
resolved with last-writer-wins at the DB level.

---

## Implementation Plan

### Phase 1: Foundation

1. **DB migration** — Create `tasks` table
2. **Ecto schema** — `Murmur.Tasks.Task` with changesets
3. **Context module** — `Murmur.Tasks` with CRUD + list queries
4. **PubSub broadcast helper** — Emit `:task_created` / `:task_updated`

### Phase 2: Agent tools

5. **`AddTask` action** — Create task + notify assignee
6. **`UpdateTask` action** — Modify status/title/description
7. **`ListTasks` action** — Query and format for LLM
8. **Register tools** in all agent profiles
9. **Extend `TeamInstructions`** — Describe task board in system prompt

### Phase 3: LiveView integration

10. **Mount** — Load tasks as stream, subscribe to PubSub topic
11. **PubSub handlers** — `:task_created`, `:task_updated`
12. **User events** — `create_task`, `update_task_status`, `edit_task`
13. **Cleanup** — Delete tasks on workspace deletion

### Phase 4: Kanban UI

14. **Task board component** — Kanban layout with four status columns
15. **Task card component** — Title, assignee, description, status controls
16. **Create/edit form** — Modal or inline form for task details
17. **Artifact panel integration** — Add "Tasks" tab to panel tab bar

### Phase 5: Polish

18. **Tests** — Context module, tool actions, LiveView interactions
19. **System prompt tuning** — Guide agents on when/how to use tasks
20. **Drag-and-drop** (optional) — JS hook for dragging cards between columns

---

## Open Questions

1. **Should agents be able to reassign tasks?** Current design says no (only
   humans can, to prevent reassignment loops). But this limits agent autonomy.
   A middle ground: agents can reassign with a notification to both parties,
   subject to the existing hop limit.

2. **Task deletion.** Current design has no delete — tasks move to `done` or
   `aborted`. Should humans be able to delete tasks? Agents?

3. **Task limits per workspace.** Should there be a cap (e.g., 100 tasks) to
   prevent runaway task creation by agents? If so, what happens when the limit
   is hit?

4. **Task history / audit log.** Should we track who changed what and when?
   The `updated_at` field shows the last change, but not a full history. An
   audit log could be added later as a separate table if needed.

5. **Subtasks / dependencies.** Out of scope for v1, but the schema could
   easily add a `parent_id` field later for hierarchical tasks.
