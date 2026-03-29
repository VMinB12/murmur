defmodule MurmurWeb.Components.Artifacts.TaskBoard do
  @moduledoc "Kanban-style task board component for the artifact panel."

  use Phoenix.Component

  import MurmurWeb.CoreComponents, only: [icon: 1]

  alias JidoMurmur.Catalog

  @statuses [
    %{
      key: :todo,
      label: "Todo",
      color: "text-slate-400",
      bg: "bg-slate-400/10",
      border: "border-slate-400/20",
      icon: "hero-clipboard-document-list"
    },
    %{
      key: :in_progress,
      label: "In Progress",
      color: "text-amber-400",
      bg: "bg-amber-400/10",
      border: "border-amber-400/20",
      icon: "hero-arrow-path"
    },
    %{
      key: :done,
      label: "Done",
      color: "text-emerald-400",
      bg: "bg-emerald-400/10",
      border: "border-emerald-400/20",
      icon: "hero-check-circle"
    },
    %{
      key: :aborted,
      label: "Aborted",
      color: "text-rose-400",
      bg: "bg-rose-400/10",
      border: "border-rose-400/20",
      icon: "hero-x-circle"
    }
  ]

  attr :tasks, :list, required: true
  attr :agent_sessions, :list, required: true
  attr :task_form, :any, required: true

  def board(assigns) do
    assigns = assign(assigns, :statuses, @statuses)

    ~H"""
    <div class="flex flex-col h-full bg-base-100">
      <%!-- Header with add form --%>
      <div class="px-4 py-3 border-b border-base-300/50">
        <div class="flex items-center justify-between mb-3">
          <div class="flex items-center gap-2">
            <.icon name="hero-clipboard-document-check" class="w-5 h-5 text-base-content/50" />
            <h2 class="text-sm font-semibold tracking-tight">Task Board</h2>
          </div>
        </div>

        <%!-- Inline create form --%>
        <.form for={@task_form} id="create-task-form" phx-submit="create_task" class="space-y-2">
          <div class="flex gap-2">
            <input
              type="text"
              name="task[title]"
              value=""
              placeholder="New task title..."
              required
              maxlength="200"
              class="flex-1 min-w-0 input input-bordered input-sm bg-base-200/50 text-sm"
            />
            <select
              name="task[assignee]"
              required
              class="select select-bordered select-sm bg-base-200/50 text-sm w-[140px] shrink-0"
            >
              <option value="" disabled selected>Assign to...</option>
              <option value="human">Human</option>
              <%= for session <- @agent_sessions do %>
                <option value={session.display_name}>{session.display_name}</option>
              <% end %>
            </select>
            <button type="submit" class="btn btn-primary btn-sm">
              <.icon name="hero-plus" class="w-4 h-4" />
            </button>
          </div>
          <input
            type="text"
            name="task[description]"
            value=""
            placeholder="Description (optional)"
            maxlength="2000"
            class="w-full input input-bordered input-sm bg-base-200/50 text-sm"
          />
        </.form>
      </div>

      <%!-- Kanban columns --%>
      <div class="flex-1 overflow-y-auto px-3 py-3">
        <div class="space-y-4">
          <%= for col <- @statuses do %>
            <.column
              status={col}
              tasks={Enum.filter(@tasks, &(&1.status == col.key))}
            />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :status, :map, required: true
  attr :tasks, :list, required: true

  defp column(assigns) do
    ~H"""
    <div>
      <div class="flex items-center gap-2 mb-2">
        <.icon name={@status.icon} class={["w-4 h-4", @status.color]} />
        <span class={["text-xs font-semibold uppercase tracking-wider", @status.color]}>
          {@status.label}
        </span>
        <span class="text-[10px] text-base-content/30">{length(@tasks)}</span>
      </div>
      <div class="space-y-2">
        <%= if @tasks == [] do %>
          <div class="text-xs text-base-content/30 px-2 py-1">
            No tasks
          </div>
        <% end %>
        <%= for task <- @tasks do %>
          <.task_card task={task} status={@status} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :task, :any, required: true
  attr :status, :map, required: true

  defp task_card(assigns) do
    agent_color = Catalog.agent_color(nil, assigns.task.assignee)
    assigns = assign(assigns, :agent_color, agent_color)

    ~H"""
    <div class={[
      "rounded-lg border px-3 py-2.5 transition-colors",
      @status.border,
      @status.bg
    ]}>
      <div class="flex items-start justify-between gap-2">
        <div class="min-w-0 flex-1">
          <p class="text-sm font-medium text-base-content leading-snug">{@task.title}</p>
          <%= if @task.description && @task.description != "" do %>
            <p class="text-xs text-base-content/50 mt-1 line-clamp-2">{@task.description}</p>
          <% end %>
        </div>
      </div>

      <div class="flex items-center justify-between mt-2">
        <div class="flex items-center gap-1.5">
          <div class={["w-2 h-2 rounded-full", @agent_color.dot]}></div>
          <span class="text-[11px] text-base-content/60">{@task.assignee}</span>
          <span class="text-[10px] text-base-content/30">· by {@task.created_by}</span>
        </div>
        <div class="flex items-center gap-1">
          <%= cond do %>
            <% @task.status == :todo -> %>
              <button
                phx-click="update_task_status"
                phx-value-task-id={@task.id}
                phx-value-status="in_progress"
                class="btn btn-ghost btn-xs text-amber-400 hover:bg-amber-400/10"
                title="Start working"
              >
                <.icon name="hero-play" class="w-3 h-3" />
              </button>
              <button
                phx-click="update_task_status"
                phx-value-task-id={@task.id}
                phx-value-status="aborted"
                class="btn btn-ghost btn-xs text-rose-400 hover:bg-rose-400/10"
                title="Abort"
              >
                <.icon name="hero-x-mark" class="w-3 h-3" />
              </button>
            <% @task.status == :in_progress -> %>
              <button
                phx-click="update_task_status"
                phx-value-task-id={@task.id}
                phx-value-status="done"
                class="btn btn-ghost btn-xs text-emerald-400 hover:bg-emerald-400/10"
                title="Mark done"
              >
                <.icon name="hero-check" class="w-3 h-3" />
              </button>
              <button
                phx-click="update_task_status"
                phx-value-task-id={@task.id}
                phx-value-status="aborted"
                class="btn btn-ghost btn-xs text-rose-400 hover:bg-rose-400/10"
                title="Abort"
              >
                <.icon name="hero-x-mark" class="w-3 h-3" />
              </button>
            <% @task.status == :done -> %>
              <button
                phx-click="update_task_status"
                phx-value-task-id={@task.id}
                phx-value-status="todo"
                class="btn btn-ghost btn-xs text-slate-400 hover:bg-slate-400/10"
                title="Reopen"
              >
                <.icon name="hero-arrow-uturn-left" class="w-3 h-3" />
              </button>
            <% @task.status == :aborted -> %>
              <button
                phx-click="update_task_status"
                phx-value-task-id={@task.id}
                phx-value-status="todo"
                class="btn btn-ghost btn-xs text-slate-400 hover:bg-slate-400/10"
                title="Reopen"
              >
                <.icon name="hero-arrow-uturn-left" class="w-3 h-3" />
              </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
