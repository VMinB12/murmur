defmodule JidoTasks.Signals.TaskUpdated do
  @moduledoc """
  Signal emitted when a task is updated on the workspace task board.

  Type: `task.updated`
  Subject: `/workspaces/{wid}/tasks/{tid}`
  """

  alias JidoTasks.Task

  use Jido.Signal,
    type: "task.updated",
    default_source: "/jido_tasks/tools/update_task",
    schema: [
      task: [
        type: {:custom, __MODULE__, :validate_task, []},
        required: true,
        doc: "Updated task struct"
      ]
    ]

  @spec validate_task(term()) :: {:ok, Task.t()} | {:error, String.t()}
  def validate_task(%Task{} = task), do: {:ok, task}
  def validate_task(_), do: {:error, "must be a JidoTasks.Task struct"}

  @doc "Build the subject URI for this signal."
  def subject(workspace_id, task_id),
    do: "/workspaces/#{workspace_id}/tasks/#{task_id}"
end
