defmodule JidoTasks.Signals.TaskUpdated do
  @moduledoc """
  Signal emitted when a task is updated on the workspace task board.

  Type: `task.updated`
  Subject: `/workspaces/{wid}/tasks/{tid}`
  """

  use Jido.Signal,
    type: "task.updated",
    default_source: "/jido_tasks/tools/update_task",
    schema: [
      task: [type: :any, required: true, doc: "Updated task struct"]
    ]

  @doc "Build the subject URI for this signal."
  def subject(workspace_id, task_id),
    do: "/workspaces/#{workspace_id}/tasks/#{task_id}"
end
