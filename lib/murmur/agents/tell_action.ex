defmodule Murmur.Agents.TellAction do
  @moduledoc """
  Jido Action for inter-agent "tell" communication.

  Allows an agent to send a message to another agent in the same workspace.
  Routes by target display_name. Respects 5-hop depth limit.
  """

  use Jido.Action,
    name: "tell",
    description:
      "Send a message to another agent in the workspace. Use when you need help from or want to communicate with a specific agent.",
    schema: [
      target_agent: [type: :string, required: true, doc: "The display name of the target agent"],
      message: [type: :string, required: true, doc: "The message to send to the target agent"]
    ]

  alias Murmur.Agents.Catalog
  alias Murmur.Workspaces

  @max_hops 5

  @impl true
  def run(params, context) do
    workspace_id = context[:workspace_id]
    sender_name = context[:sender_name]
    hop_count = context[:hop_count] || 0

    with :ok <- validate_hop_count(hop_count),
         %{} = target <- Workspaces.find_agent_session_by_name(workspace_id, params.target_agent) do
      prefixed_message = "[#{sender_name}]: #{params.message}"

      case deliver_message(target, prefixed_message, hop_count + 1) do
        :ok ->
          {:ok, %{delivered: true, target: params.target_agent}}

        {:error, reason} ->
          {:error, "Failed to deliver to '#{params.target_agent}': #{inspect(reason)}"}
      end
    else
      {:error, _} = error -> error
      nil -> {:error, "Agent '#{params.target_agent}' not found in this workspace."}
    end
  end

  defp validate_hop_count(hop_count) when hop_count >= @max_hops,
    do: {:error, "Maximum inter-agent hop depth (#{@max_hops}) reached."}

  defp validate_hop_count(_), do: :ok

  defp deliver_message(target_session, message, hop_count) do
    pid = Murmur.Jido.whereis(target_session.id)

    if pid do
      agent_module = Catalog.agent_module(target_session.agent_profile_id)
      topic = "workspace:#{target_session.workspace_id}:agent:#{target_session.id}"

      # Broadcast inter-agent message to PubSub for LiveView display
      inter_msg = %{
        id: Ecto.UUID.generate(),
        role: "user",
        content: message,
        sender_name: String.replace(message, ~r/^\[([^\]]+)\]:.*/, "\\1"),
        metadata: %{"hop_count" => hop_count}
      }

      Phoenix.PubSub.broadcast(Murmur.PubSub, topic, {:new_message, target_session.id, inter_msg})

      # Send to the agent via ask/await in an async task
      Task.Supervisor.start_child(Murmur.Jido.task_supervisor_name(), fn ->
        try do
          {:ok, req} = agent_module.ask(pid, message)
          result = agent_module.await(req, timeout: 120_000)

          case result do
            {:ok, response} ->
              Phoenix.PubSub.broadcast(
                Murmur.PubSub,
                topic,
                {:message_completed, target_session.id, response}
              )

            {:error, reason} ->
              Phoenix.PubSub.broadcast(
                Murmur.PubSub,
                topic,
                {:request_failed, target_session.id, reason}
              )
          end
        rescue
          e ->
            Phoenix.PubSub.broadcast(
              Murmur.PubSub,
              topic,
              {:request_failed, target_session.id, Exception.message(e)}
            )
        end
      end)

      :ok
    else
      {:error, :agent_not_running}
    end
  end
end
