defmodule JidoMurmur.Ingress.ProgrammaticDelivery do
  @moduledoc """
  Shared delivery path for visible programmatic ingress messages.

  This helper keeps the visible `message.received` payload aligned with the
  canonical ingress input delivered through `JidoMurmur.Ingress`.
  """

  alias JidoMurmur.ActorIdentity
  alias JidoMurmur.Ingress
  alias JidoMurmur.Ingress.Input
  alias JidoMurmur.Signals.MessageReceived

  @type session_like :: %{
          required(:id) => String.t(),
          required(:workspace_id) => String.t()
        }

  @invalid_input_reasons [
    :empty_content,
    :missing_source,
    :invalid_source,
    :invalid_refs,
    :missing_interaction_id,
    :invalid_interaction_id,
    :missing_workspace_id,
    :invalid_workspace_id,
    :invalid_sender_name,
    :invalid_origin_actor,
    :invalid_sender_trace_id,
    :invalid_hop_count,
    :invalid_expected_request_id
  ]

  @spec deliver(session_like(), String.t(), keyword()) ::
          :queued | :agent_not_running | {:error, {:invalid_input, Input.validation_error()}}
  def deliver(session, content, opts \\ []) when is_binary(content) and is_list(opts) do
    with {:ok, message_kind} <- normalize_message_kind(Keyword.get(opts, :kind, Keyword.get(opts, :via))),
         {:ok, input} <-
           Input.programmatic_message(session, content,
             via: Keyword.get(opts, :via),
             interaction_id: Keyword.get(opts, :interaction_id),
             sender_name: Keyword.get(opts, :sender_name),
             origin_actor: Keyword.get(opts, :origin_actor),
             sender_trace_id: Keyword.get(opts, :sender_trace_id),
             expected_request_id: Keyword.get(opts, :expected_request_id),
             refs: Keyword.get(opts, :refs, %{})
           ),
         :queued <- Ingress.deliver_input(session, input) do
      broadcast_received(session, input, message_kind)
      :queued
    else
      {:error, reason} when reason in @invalid_input_reasons ->
        {:error, {:invalid_input, reason}}

      :agent_not_running ->
        :agent_not_running

      {:error, {:invalid_input, _reason}} = error ->
        error
    end
  end

  defp broadcast_received(session, input, message_kind) do
    {:ok, metadata} = Input.metadata(input)

    signal =
      MessageReceived.new!(
        %{
          session_id: session.id,
          message: %{
            id: Uniq.UUID.uuid7(),
            role: "user",
            content: input.content,
            kind: message_kind,
            interaction_id: metadata.interaction_id,
            sender_name: metadata.sender_name,
            origin_actor: ActorIdentity.serialize(metadata.origin_actor),
            sender_trace_id: metadata.sender_trace_id,
            hop_count: metadata.hop_count
          }
        },
        subject: MessageReceived.subject(session.workspace_id, session.id)
      )

    Phoenix.PubSub.broadcast(JidoMurmur.pubsub(), topic(session), signal)
  end

  defp normalize_message_kind(value) when is_atom(value) or is_binary(value), do: {:ok, value}
  defp normalize_message_kind(_value), do: {:error, :invalid_source}

  defp topic(session) do
    JidoMurmur.Topics.agent_messages(session.workspace_id, session.id)
  end
end
