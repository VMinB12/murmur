defmodule JidoTasks.Signals.TaskCreated do
  @moduledoc """
  Signal emitted when a new task is created on the workspace task board.

  Type: `task.created`
  Subject: `/workspaces/{wid}/tasks/{tid}`
  """

  use Jido.Signal,
    type: "task.created",
    default_source: "/jido_tasks/tools/add_task",
    schema: [
      task: [type: :any, required: true, doc: "Created task struct"]
    ]

  @doc "Build the subject URI for this signal."
  def subject(workspace_id, task_id),
    do: "/workspaces/#{workspace_id}/tasks/#{task_id}"
end
