defmodule JidoMurmur.Ingress.VisibleMessage do
  @moduledoc false

  alias Jido.Signal.ID, as: SignalID
  alias JidoMurmur.ActorIdentity
  alias JidoMurmur.Ingress.Input
  alias JidoMurmur.Signals.MessageReceived

  @message_id_key :message_id
  @first_seen_at_key :message_first_seen_at
  @first_seen_seq_key :message_first_seen_seq
  @reserved_extra_keys [@message_id_key, @first_seen_at_key, @first_seen_seq_key]

  @spec attach_identity_refs(map()) :: map()
  def attach_identity_refs(%{} = extra_refs) do
    message_id = Map.get(extra_refs, @message_id_key) || SignalID.generate!()

    extra_refs
    |> Map.put(@message_id_key, message_id)
    |> Map.put(@first_seen_at_key, Map.get(extra_refs, @first_seen_at_key) || first_seen_at(message_id))
    |> Map.put(@first_seen_seq_key, Map.get(extra_refs, @first_seen_seq_key) || first_seen_seq(message_id))
  end

  def attach_identity_refs(other), do: other

  @spec broadcast_received(map(), Input.t(), atom() | String.t()) :: :ok
  def broadcast_received(session, %Input{} = input, message_kind) do
    {:ok, metadata} = Input.metadata(input)
    identity = identity(metadata.extra)

    message =
      metadata.extra
      |> Map.drop(@reserved_extra_keys)
      |> Map.merge(%{
        id: identity.message_id,
        role: "user",
        content: input.content,
        kind: message_kind,
        sender_name: metadata.sender_name,
        first_seen_at: identity.first_seen_at,
        first_seen_seq: identity.first_seen_seq,
        origin_actor: ActorIdentity.serialize(metadata.origin_actor),
        sender_trace_id: metadata.sender_trace_id,
        hop_count: metadata.hop_count
      })
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    signal =
      MessageReceived.new!(
        %{session_id: session.id, message: message},
        subject: MessageReceived.subject(session.workspace_id, session.id)
      )

    Phoenix.PubSub.broadcast(JidoMurmur.pubsub(), topic(session), signal)
  end

  defp identity(extra_refs) do
    message_id = Map.get(extra_refs, @message_id_key) || SignalID.generate!()

    %{
      message_id: message_id,
      first_seen_at: Map.get(extra_refs, @first_seen_at_key) || first_seen_at(message_id),
      first_seen_seq: Map.get(extra_refs, @first_seen_seq_key) || first_seen_seq(message_id)
    }
  end

  defp first_seen_at(message_id) when is_binary(message_id) do
    if SignalID.valid?(message_id), do: SignalID.extract_timestamp(message_id), else: generated_first_seen_at()
  end

  defp first_seen_at(_message_id), do: generated_first_seen_at()

  defp first_seen_seq(message_id) when is_binary(message_id) do
    if SignalID.valid?(message_id), do: SignalID.sequence_number(message_id), else: generated_first_seen_seq()
  end

  defp first_seen_seq(_message_id), do: generated_first_seen_seq()

  defp generated_first_seen_at do
    generated_id = SignalID.generate!()
    SignalID.extract_timestamp(generated_id)
  end

  defp generated_first_seen_seq do
    generated_id = SignalID.generate!()
    SignalID.sequence_number(generated_id)
  end

  defp topic(session) do
    JidoMurmur.Topics.agent_messages(session.workspace_id, session.id)
  end
end
