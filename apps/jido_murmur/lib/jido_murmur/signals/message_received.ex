defmodule JidoMurmur.Signals.MessageReceived do
  @moduledoc """
  Signal emitted when an inter-agent message is delivered.

  Type: `murmur.message.received`
  Subject: `/workspaces/{wid}/agents/{sid}`
  """

  use Jido.Signal,
    type: "murmur.message.received",
    default_source: "/jido_murmur/tell_action",
    schema: [
      session_id: [type: :string, required: true, doc: "Target agent session ID"],
      message: [type: :map, required: true, doc: "Message content map"]
    ]

  @doc "Build the subject URI for this signal."
  def subject(workspace_id, session_id),
    do: "/workspaces/#{workspace_id}/agents/#{session_id}"
end
