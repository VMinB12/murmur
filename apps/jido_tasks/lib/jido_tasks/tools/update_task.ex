defmodule JidoTasks.Tools.UpdateTask do
  @moduledoc "Agent tool to update a task's status, title, or description on the task board."

  use Jido.Action,
    name: "update_task",
    description: """
    Update an existing task on the workspace task board.
    You can change the status, title, or description.
    You cannot change the assignee — if a task should be handled by someone else,
    mark it as done and create a new task assigned to them.
    """,
    schema: [
      task_id: [type: :string, required: true, doc: "The task ID to update"],
      status: [type: :string, doc: "New status: todo, in_progress, done, or aborted"],
      title: [type: :string, doc: "New title (max 200 chars)"],
      description: [type: :string, doc: "New or updated description (max 2000 chars)"]
    ]

  alias JidoTasks.Tasks

  @valid_statuses ~w(todo in_progress done aborted)

  @impl true
  def run(params, context) do
    workspace_id = context[:workspace_id]

    with %{} = task <- Tasks.get_task(params.task_id),
         :ok <- verify_workspace(task, workspace_id) do
      do_update(task, params, workspace_id)
    else
      nil -> {:error, "Task not found: #{params.task_id}"}
      {:error, _} = err -> err
    end
  end

  defp verify_workspace(task, workspace_id) do
    if task.workspace_id == workspace_id, do: :ok, else: {:error, "Task not found in this workspace"}
  end

  defp do_update(task, params, workspace_id) do
    attrs = build_attrs(params)

    case Tasks.update_task(task, attrs) do
      {:ok, updated} ->
        broadcast_task_updated(workspace_id, updated)
        {:ok, %{result: "Task updated: \"#{updated.title}\" is now #{updated.status}"}}

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        {:error, "Failed to update task: #{inspect(errors)}"}
    end
  end

  defp build_attrs(params) do
    %{}
    |> maybe_put(:title, params[:title])
    |> maybe_put_status(params[:status])
    |> maybe_put(:description, params[:description])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_status(map, nil), do: map

  defp maybe_put_status(map, status) when status in @valid_statuses do
    Map.put(map, :status, String.to_existing_atom(status))
  end

  defp maybe_put_status(_map, status) do
    raise "Invalid status: #{status}. Must be one of: #{Enum.join(@valid_statuses, ", ")}"
  end

  defp broadcast_task_updated(workspace_id, task) do
    Phoenix.PubSub.broadcast(
      JidoTasks.pubsub(),
      Tasks.tasks_topic(workspace_id),
      {:task_updated, task}
    )
  end
end
