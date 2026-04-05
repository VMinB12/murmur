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
          required(:sender_trace_id) => String.t() | nil,
          optional(:hop_count) => non_neg_integer()
        }

  use Jido.Signal,
    type: "murmur.message.received",
    default_source: "/jido_murmur/ingress/programmatic_delivery",
    schema: [
      session_id: [type: :string, required: true, doc: "Target agent session ID"],
      message: [
        type: {:custom, __MODULE__, :validate_message, []},
        required: true,
        doc: "Delivered message payload"
      ]
    ]

  @spec validate_message(term()) :: {:ok, message_payload()} | {:error, String.t()}
  def validate_message(%{} = message) do
    with :ok <- validate_required_binary(message, :id),
         :ok <- validate_required_binary(message, :role),
         :ok <- validate_required_binary(message, :content),
         :ok <- validate_kind(Map.get(message, :kind)),
         :ok <- validate_required_binary(message, :interaction_id),
         :ok <- validate_required_binary(message, :sender_name),
         :ok <- validate_optional_binary(Map.get(message, :sender_trace_id)),
         :ok <- validate_hop_count(Map.get(message, :hop_count)) do
      {:ok, message}
    else
      {:error, _reason} -> invalid_message_error()
    end
  end

  def validate_message(_), do: invalid_message_error()

  @doc "Build the subject URI for this signal."
  def subject(workspace_id, session_id),
    do: "/workspaces/#{workspace_id}/agents/#{session_id}"

  defp validate_required_binary(message, key) do
    case Map.get(message, key) do
      value when is_binary(value) -> :ok
      _ -> {:error, key}
    end
  end

  defp validate_optional_binary(nil), do: :ok
  defp validate_optional_binary(value) when is_binary(value), do: :ok
  defp validate_optional_binary(_value), do: {:error, :sender_trace_id}

  defp validate_kind(value) when is_atom(value) or is_binary(value), do: :ok
  defp validate_kind(_value), do: {:error, :kind}

  defp validate_hop_count(nil), do: :ok
  defp validate_hop_count(value) when is_integer(value) and value >= 0, do: :ok
  defp validate_hop_count(_value), do: {:error, :hop_count}

  defp invalid_message_error do
    {:error,
     "must be a message map with id, role, content, kind, interaction_id, sender_name, and sender_trace_id fields"}
  end
end
