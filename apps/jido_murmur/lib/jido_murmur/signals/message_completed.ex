defmodule JidoMurmur.Signals.MessageCompleted do
  @moduledoc """
  Signal emitted when an agent finishes processing a message.

  Type: `murmur.message.completed`
  Subject: `/workspaces/{wid}/agents/{sid}`
  """

  use Jido.Signal,
    type: "murmur.message.completed",
    default_source: "/jido_murmur/runner",
    schema: [
      session_id: [type: :string, required: true, doc: "Agent session ID"],
      response: [type: :any, required: true, doc: "Agent response content"]
    ]

  @doc "Build the subject URI for this signal."
  def subject(workspace_id, session_id),
    do: "/workspaces/#{workspace_id}/agents/#{session_id}"
end
