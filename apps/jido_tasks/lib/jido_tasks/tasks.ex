defmodule JidoTasks.Tasks do
  @moduledoc "Context for managing shared tasks within a workspace."

  import Ecto.Query

  alias JidoTasks.Task

  @doc "Lists tasks for a workspace, optionally filtered by status."
  def list_tasks(workspace_id, opts \\ []) do
    :telemetry.span([:jido_tasks, :task, :list], %{workspace_id: workspace_id}, fn ->
      query = from(t in Task, where: t.workspace_id == ^workspace_id, order_by: [asc: t.inserted_at])

      query =
        case Keyword.get(opts, :status) do
          nil -> query
          status -> where(query, [t], t.status == ^status)
        end

      tasks = JidoTasks.repo().all(query)
      {tasks, %{workspace_id: workspace_id, count: length(tasks)}}
    end)
  end

  @doc "Gets a single task by ID. Raises if not found."
  def get_task!(id), do: JidoTasks.repo().get!(Task, id)

  @doc "Gets a single task by ID. Returns nil if not found."
  def get_task(id), do: JidoTasks.repo().get(Task, id)

  @doc "Creates a task in the given workspace."
  def create_task(workspace_id, attrs, created_by) do
    :telemetry.span([:jido_tasks, :task, :create], %{workspace_id: workspace_id}, fn ->
      result =
        %Task{workspace_id: workspace_id, created_by: created_by}
        |> Task.create_changeset(attrs)
        |> JidoTasks.repo().insert()

      case result do
        {:ok, task} -> {result, %{task_id: task.id, workspace_id: workspace_id}}
        {:error, _} -> {result, %{workspace_id: workspace_id}}
      end
    end)
  end

  @doc "Updates an existing task's title, description, or status."
  def update_task(%Task{} = task, attrs) do
    old_status = task.status

    :telemetry.span([:jido_tasks, :task, :update], %{task_id: task.id}, fn ->
      result =
        task
        |> Task.update_changeset(attrs)
        |> JidoTasks.repo().update()

      case result do
        {:ok, updated} ->
          {result, %{task_id: task.id, old_status: old_status, new_status: updated.status}}

        {:error, _} ->
          {result, %{task_id: task.id, old_status: old_status}}
      end
    end)
  end

  @doc "Returns task counts grouped by status for a workspace."
  def task_stats(workspace_id) do
    from(t in Task,
      where: t.workspace_id == ^workspace_id,
      group_by: t.status,
      select: {t.status, count(t.id)}
    )
    |> JidoTasks.repo().all()
    |> Map.new()
  end

  @doc "Deletes all tasks for a workspace."
  def delete_tasks_for_workspace(workspace_id) do
    JidoTasks.repo().delete_all(from(t in Task, where: t.workspace_id == ^workspace_id))
  end

  @doc "PubSub topic for task updates in a workspace."
  def tasks_topic(workspace_id), do: JidoMurmur.Topics.workspace_tasks(workspace_id)
end
