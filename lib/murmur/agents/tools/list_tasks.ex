defmodule Murmur.Agents.Tools.ListTasks do
  @moduledoc "Agent tool to list tasks from the shared workspace task board."

  use Jido.Action,
    name: "list_tasks",
    description:
      "List tasks from the workspace task board. Optionally filter by status: todo, in_progress, done, or aborted.",
    schema: [
      status: [type: :string, doc: "Filter by status: todo, in_progress, done, or aborted"]
    ]

  alias Murmur.Tasks

  @valid_statuses ~w(todo in_progress done aborted)

  @impl true
  def run(params, context) do
    workspace_id = context[:workspace_id]

    case parse_status_filter(params[:status]) do
      {:error, _} = err -> err
      opts -> do_list(workspace_id, opts, params)
    end
  end

  defp parse_status_filter(nil), do: []

  defp parse_status_filter(status) when status in @valid_statuses, do: [status: String.to_existing_atom(status)]

  defp parse_status_filter(status),
    do: {:error, "Invalid status filter: #{status}. Must be one of: #{Enum.join(@valid_statuses, ", ")}"}

  defp do_list(workspace_id, opts, params) do
    tasks = Tasks.list_tasks(workspace_id, opts)
    formatted = Enum.map_join(tasks, "\n", &format_task/1)

    summary =
      cond do
        formatted == "" && params[:status] -> "No tasks with status \"#{params.status}\"."
        formatted == "" -> "No tasks on the board yet."
        true -> "#{length(tasks)} task(s):\n#{formatted}"
      end

    {:ok, %{result: summary}}
  end

  defp format_task(t) do
    line = "- [#{t.status}] \"#{t.title}\" (assigned to: #{t.assignee}, id: #{t.id})"

    if t.description && t.description != "" do
      line <> "\n  #{String.slice(t.description, 0, 200)}"
    else
      line
    end
  end
end
