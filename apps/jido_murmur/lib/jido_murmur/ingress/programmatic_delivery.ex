defmodule JidoMurmur.Ingress.ProgrammaticDelivery do
  @moduledoc """
  Shared delivery path for visible programmatic ingress messages.

  This helper keeps the visible `message.received` payload aligned with the
  canonical ingress input delivered through `JidoMurmur.Ingress`.
  """

  alias JidoMurmur.ConversationProjector
  alias JidoMurmur.Ingress
  alias JidoMurmur.Ingress.Input
  alias JidoMurmur.Ingress.VisibleMessage
  alias JidoMurmur.SessionContract

  @type session_like :: SessionContract.target()

  @invalid_input_reasons [
    :empty_content,
    :missing_source,
    :invalid_source,
    :invalid_refs,
    :missing_workspace_id,
    :invalid_workspace_id,
    :invalid_sender_name,
    :invalid_origin_actor,
    :invalid_sender_trace_id,
    :invalid_hop_count,
    :invalid_expected_request_id
  ]

  @spec deliver(session_like(), String.t(), list()) ::
          :queued | :agent_not_running | {:error, {:invalid_input, Input.validation_error()}}
  def deliver(%{id: _, workspace_id: _, agent_profile_id: _, display_name: _} = session, content, opts \\ [])
      when is_binary(content) and is_list(opts) do
    case normalize_message_kind(Keyword.get(opts, :kind, Keyword.get(opts, :via))) do
      {:ok, message_kind} ->
        deliver_programmatic_message(session, content, opts, message_kind)

      {:error, reason} when reason in @invalid_input_reasons ->
        {:error, {:invalid_input, reason}}
    end
  end

  defp normalize_message_kind(value) when is_atom(value) or is_binary(value), do: {:ok, value}
  defp normalize_message_kind(_value), do: {:error, :invalid_source}

  defp deliver_programmatic_message(session, content, opts, message_kind) do
    case Input.programmatic_message(session, content,
           via: Keyword.get(opts, :via),
           sender_name: Keyword.get(opts, :sender_name),
           origin_actor: Keyword.get(opts, :origin_actor),
           sender_trace_id: Keyword.get(opts, :sender_trace_id),
           expected_request_id: Keyword.get(opts, :expected_request_id),
           refs: VisibleMessage.attach_identity_refs(Keyword.get(opts, :refs, %{}))
         ) do
      {:ok, input} ->
        message = VisibleMessage.build_message(input, message_kind)
        deliver_visible_input(session, input, message)

      {:error, reason} when reason in @invalid_input_reasons ->
        {:error, {:invalid_input, reason}}
    end
  end

  defp deliver_visible_input(session, %Input{} = input, message) do
    case Ingress.ensure_started(session) do
      {:ok, pid} -> queue_visible_input(pid, session, input, message)
      {:error, :agent_not_running} -> :agent_not_running
    end
  end

  defp queue_visible_input(pid, session, %Input{} = input, message) when is_pid(pid) do
    _ = ConversationProjector.put_received_message(session, message)

    case GenServer.call(pid, {:deliver, session, input}) do
      :queued ->
        VisibleMessage.broadcast_received(session, message)
        :queued

      :agent_not_running ->
        :agent_not_running
    end
  end
end
