defmodule JidoMurmur.Ingress.ProgrammaticDelivery do
  @moduledoc """
  Shared delivery path for visible programmatic ingress messages.

  This helper keeps the visible `message.received` payload aligned with the
  canonical ingress input delivered through `JidoMurmur.Ingress`.
  """

  alias JidoMurmur.Ingress
  alias JidoMurmur.Ingress.{Input, VisibleMessage}

  @type session_like :: %{
          required(:id) => String.t(),
      required(:workspace_id) => String.t(),
      required(:agent_profile_id) => String.t(),
      required(:display_name) => String.t()
        }

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

  @spec deliver(session_like(), String.t(), keyword()) ::
          :queued | :agent_not_running | {:error, {:invalid_input, Input.validation_error()}}
  def deliver(%{id: _, workspace_id: _, agent_profile_id: _, display_name: _} = session, content, opts \\ [])
      when is_binary(content) and is_list(opts) do
    with {:ok, message_kind} <- normalize_message_kind(Keyword.get(opts, :kind, Keyword.get(opts, :via))),
         {:ok, input} <-
           Input.programmatic_message(session, content,
             via: Keyword.get(opts, :via),
             sender_name: Keyword.get(opts, :sender_name),
             origin_actor: Keyword.get(opts, :origin_actor),
             sender_trace_id: Keyword.get(opts, :sender_trace_id),
             expected_request_id: Keyword.get(opts, :expected_request_id),
             refs: VisibleMessage.attach_identity_refs(Keyword.get(opts, :refs, %{}))
           ),
         :queued <- Ingress.deliver_input(session, input) do
      VisibleMessage.broadcast_received(session, input, message_kind)
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

  defp normalize_message_kind(value) when is_atom(value) or is_binary(value), do: {:ok, value}
  defp normalize_message_kind(_value), do: {:error, :invalid_source}
end
