defmodule JidoMurmur.Observability do
  @moduledoc """
  Murmur-owned observability entrypoint.

  Owns trace semantics for agent turns, LLM calls, tool calls, and
  cross-agent correlation while remaining compatible with Arize Phoenix.
  """

  alias JidoMurmur.Observability.Store

  @active_llm_call_key {__MODULE__, :active_llm_call_id}

  @type message_envelope :: %{
          required(:id) => String.t(),
          required(:content) => String.t(),
          required(:role) => String.t(),
          required(:kind) => atom(),
          required(:interaction_id) => String.t(),
          optional(:sender_name) => String.t() | nil,
          optional(:sender_trace_id) => String.t() | nil
        }

  def enabled? do
    Application.get_env(:jido_murmur, :observability, [])
    |> Keyword.get(:enabled, true)
  end

  def capture_content? do
    Application.get_env(:jido_murmur, :observability, [])
    |> Keyword.get(:capture_content, true)
  end

  def next_interaction_id, do: Uniq.UUID.uuid7()

  def build_message_envelope(content, opts \\ []) when is_binary(content) do
    %{
      id: Keyword.get(opts, :id, Uniq.UUID.uuid7()),
      role: Keyword.get(opts, :role, "user"),
      content: content,
      kind: Keyword.get(opts, :kind, :direct),
      interaction_id: Keyword.get(opts, :interaction_id, next_interaction_id()),
      sender_name: Keyword.get(opts, :sender_name),
      sender_trace_id: Keyword.get(opts, :sender_trace_id)
    }
  end

  def start_turn(attrs), do: Store.start_turn(attrs)
  def finish_turn(request_id, attrs), do: Store.finish_turn(request_id, attrs)
  def fail_turn(request_id, reason, attrs \\ %{}), do: Store.fail_turn(request_id, reason, attrs)
  def record_signal(signal, context), do: Store.record_signal(signal, context)
  def record_injected_messages(agent_id, envelopes), do: Store.record_injected_messages(agent_id, envelopes)
    def record_prepared_llm_input(%{llm_call_id: call_id}, messages) when is_binary(call_id) and is_list(messages),
      do: Store.record_prepared_llm_input(call_id, messages)

    def record_prepared_llm_input(call_id, messages) when is_binary(call_id) and is_list(messages),
      do: Store.record_prepared_llm_input(call_id, messages)

    def record_prepared_llm_input(_call_id_or_state, _messages), do: :ok
  def record_req_llm_start(metadata, agent_context \\ nil), do: Store.record_req_llm_start(metadata, agent_context)
  def record_req_llm_stop(measurements, metadata), do: Store.record_req_llm_stop(measurements, metadata)
  def record_req_llm_exception(metadata), do: Store.record_req_llm_exception(metadata)

  def set_active_llm_call_id(call_id) when is_binary(call_id) do
    Process.put(@active_llm_call_key, call_id)
    :ok
  end

  def clear_active_llm_call_id do
    Process.delete(@active_llm_call_key)
    :ok
  end

  def current_active_llm_call_id do
    Process.get(@active_llm_call_key)
  end
end
