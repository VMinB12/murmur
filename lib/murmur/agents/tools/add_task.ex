defmodule Murmur.Agents.Tools.AddTask do
  @moduledoc "Agent tool to create a task on the shared workspace task board."

  use Jido.Action,
    name: "add_task",
    description: """
    Create a new task on the shared workspace task board.
    Assign it to yourself, another agent by display name, or "human" for the user.
    The assigned agent will be notified immediately.
    """,
    schema: [
      title: [type: :string, required: true, doc: "Task title (max 200 chars)"],
      description: [type: :string, doc: "Optional task description (max 2000 chars)"],
      assignee: [
        type: :string,
        required: true,
        doc: "Display name of the agent to assign, or \"human\" for the user"
      ]
    ]

  alias Jido.Signal.ID
  alias Murmur.Agents.Runner
  alias Murmur.Tasks
  alias Murmur.Workspaces

  @impl true
  def run(params, context) do
    workspace_id = context[:workspace_id]
    sender_name = context[:sender_name]

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
        {:ok, %{result: format_success(task, workspace_id)}}

      {:error, changeset} ->
        {:error, "Failed to create task: #{inspect(format_errors(changeset))}"}
    end
  end

  defp format_success(task, workspace_id) do
    stats = Tasks.task_stats(workspace_id)
    total = Enum.reduce(stats, 0, fn {_status, count}, acc -> acc + count end)

    "Task created: \"#{task.title}\" assigned to #{task.assignee} (id: #{task.id}). " <>
      "Board now has #{total} task(s): " <>
      "#{Map.get(stats, :todo, 0)} todo, #{Map.get(stats, :in_progress, 0)} in progress, " <>
      "#{Map.get(stats, :done, 0)} done, #{Map.get(stats, :aborted, 0)} aborted."
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp broadcast_task_created(workspace_id, task) do
    Phoenix.PubSub.broadcast(
      Murmur.PubSub,
      Tasks.tasks_topic(workspace_id),
      {:task_created, task}
    )
  end

  defp notify_assignee(workspace_id, task, sender_name) do
    if task.assignee == "human" or task.assignee == sender_name do
      :ok
    else
      do_notify_assignee(workspace_id, task, sender_name)
    end
  end

  defp do_notify_assignee(workspace_id, task, sender_name) do
    case Workspaces.find_agent_session_by_name(workspace_id, task.assignee) do
      nil ->
        :ok

      target_session ->
        message = build_notification(task, sender_name)
        topic = "workspace:#{workspace_id}:agent:#{target_session.id}"

        inter_msg = %{
          id: ID.generate!(),
          role: "user",
          content: message,
          sender_name: sender_name
        }

        Phoenix.PubSub.broadcast(Murmur.PubSub, topic, {:new_message, target_session.id, inter_msg})
        Runner.send_message(target_session, message)
    end
  end

  defp build_notification(task, sender_name) do
    "[#{sender_name}] assigned you a task: \"#{task.title}\"" <>
      if(task.description, do: "\nDescription: #{task.description}", else: "") <>
      "\nTask ID: #{task.id}" <>
      "\nUse update_task to change its status when you start or complete it."
  end
end
