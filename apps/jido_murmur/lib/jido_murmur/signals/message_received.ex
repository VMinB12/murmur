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
      required(:kind) => atom() | String.t(),
      required(:interaction_id) => String.t(),
      required(:sender_name) => String.t(),
      required(:sender_trace_id) => String.t() | nil
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
  def validate_message(%{
        id: id,
        role: role,
        content: content,
        kind: kind,
        interaction_id: interaction_id,
        sender_name: sender_name,
        sender_trace_id: sender_trace_id
      } = message)
      when is_binary(id) and is_binary(role) and is_binary(content) and
             is_binary(interaction_id) and is_binary(sender_name) and
             (is_atom(kind) or is_binary(kind)) and (is_binary(sender_trace_id) or is_nil(sender_trace_id)) do
    {:ok, message}
  end

  def validate_message(_),
    do:
      {:error,
       "must be a message map with id, role, content, kind, interaction_id, sender_name, and sender_trace_id fields"}

  @doc "Build the subject URI for this signal."
  def subject(workspace_id, session_id),
    do: "/workspaces/#{workspace_id}/agents/#{session_id}"
end
