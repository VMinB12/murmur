defmodule JidoMurmur.Signals.MessageReceived do
  @moduledoc """
  Signal emitted when an inter-agent message is delivered.

  Type: `murmur.message.received`
  Subject: `/workspaces/{wid}/agents/{sid}`
  """

  @type message_payload :: %{
          required(:id) => String.t(),
          required(:role) => String.t(),
          required(:content) => String.t(),
          optional(:sender_name) => String.t() | nil,
          optional(:sender_trace_id) => String.t() | nil
        }

  use Jido.Signal,
    type: "murmur.message.received",
    default_source: "/jido_murmur/tell_action",
    schema: [
      session_id: [type: :string, required: true, doc: "Target agent session ID"],
      message: [
        type: {:custom, __MODULE__, :validate_message, []},
        required: true,
        doc: "Delivered message payload"
      ]
    ]

  @spec validate_message(term()) :: {:ok, message_payload()} | {:error, String.t()}
  def validate_message(%{id: id, role: role, content: content} = message)
      when is_binary(id) and is_binary(role) and is_binary(content) do
    {:ok, message}
  end

  def validate_message(_),
    do: {:error, "must be a message map with string id, role, and content fields"}

  @doc "Build the subject URI for this signal."
  def subject(workspace_id, session_id),
    do: "/workspaces/#{workspace_id}/agents/#{session_id}"
end
