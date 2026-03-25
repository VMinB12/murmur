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

  alias Murmur.Agents.PubSubBridge
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
      topic = PubSubBridge.topic(target_session.workspace_id, target_session.id)

      # Persist and broadcast the inter-agent message
      {:ok, msg} =
        Murmur.Chat.create_message(%{
          agent_session_id: target_session.id,
          role: "user",
          content: message,
          sender_name: String.replace(message, ~r/^\[([^\]]+)\]:.*/, "\\1"),
          metadata: %{"hop_count" => hop_count}
        })

      Phoenix.PubSub.broadcast(Murmur.PubSub, topic, {:new_message, target_session.id, msg})

      # Send to the agent
      PubSubBridge.send_message(target_session, message)
      :ok
    else
      {:error, :agent_not_running}
    end
  end
end
