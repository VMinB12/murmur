defmodule JidoMurmur.Signals.MessageCompleted do
  @moduledoc """
  Signal emitted when an agent finishes processing a message.

  Type: `murmur.message.completed`
  Subject: `/workspaces/{wid}/agents/{sid}`
  """

  @type response_payload :: String.t() | map()

  use Jido.Signal,
    type: "murmur.message.completed",
    default_source: "/jido_murmur/runner",
    schema: [
      session_id: [type: :string, required: true, doc: "Agent session ID"],
      response: [
        type: {:custom, __MODULE__, :validate_response, []},
        required: true,
        doc: "Agent response content"
      ]
    ]

  @spec validate_response(term()) :: {:ok, response_payload()} | {:error, String.t()}
  def validate_response(response) when is_binary(response) or is_map(response), do: {:ok, response}
  def validate_response(_), do: {:error, "must be a string or map response payload"}

  @doc "Build the subject URI for this signal."
  def subject(workspace_id, session_id),
    do: "/workspaces/#{workspace_id}/agents/#{session_id}"
end
