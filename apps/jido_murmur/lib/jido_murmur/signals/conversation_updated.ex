defmodule JidoMurmur.Signals.ConversationUpdated do
  @moduledoc """
  Signal emitted when Murmur's canonical conversation projector updates the
  visible state for one session.

  Type: `murmur.conversation.updated`
  Subject: `/workspaces/{wid}/agents/{sid}`
  """

  use Jido.Signal,
    type: "murmur.conversation.updated",
    default_source: "/jido_murmur/conversation_projector",
    schema: [
      session_id: [type: :string, required: true, doc: "Agent session ID"],
      message: [type: {:custom, __MODULE__, :validate_message, []}, required: true, doc: "Canonical message update for the affected turn"]
    ]

  @spec validate_message(term()) :: {:ok, map()} | {:error, String.t()}
  def validate_message(%{} = message) do
    case {Map.get(message, :id), Map.get(message, :role), Map.get(message, :content)} do
      {id, role, content} when is_binary(id) and is_binary(role) and is_binary(content) -> {:ok, message}
      _ -> {:error, "must be a message-like map with id, role, and content fields"}
    end
  end

  def validate_message(_), do: {:error, "must be a message-like map with id, role, and content fields"}

  def subject(workspace_id, session_id), do: "/workspaces/#{workspace_id}/agents/#{session_id}"
end
