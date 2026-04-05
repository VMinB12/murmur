defmodule JidoMurmur.Observability do
  @moduledoc """
  Murmur-owned observability entrypoint.

  Owns trace semantics for agent turns, LLM calls, tool calls, and
  cross-agent correlation while remaining compatible with Arize Phoenix.
  """

  alias JidoMurmur.Observability.Store

  @active_llm_call_key {__MODULE__, :active_llm_call_id}
  @enabled_override_key {__MODULE__, :enabled_override}
  @capture_content_override_key {__MODULE__, :capture_content_override}

  @spec enabled?() :: boolean()
  def enabled? do
    case runtime_override(@enabled_override_key) do
      false -> false
      true -> true
      :__unset__ -> truthy_observability_config(:enabled, true)
    end
  end

  @spec capture_content?() :: boolean()
  def capture_content? do
    case runtime_override(@capture_content_override_key) do
      false -> false
      true -> true
      :__unset__ -> truthy_observability_config(:capture_content, true)
    end
  end

  def captured_content(value) do
    if capture_content?(), do: value, else: nil
  end

  def start_turn(attrs), do: Store.start_turn(attrs)
  def finish_turn(request_id, attrs), do: Store.finish_turn(request_id, attrs)
  def fail_turn(request_id, reason, attrs \\ %{}), do: Store.fail_turn(request_id, reason, attrs)
  def record_signal(signal, context), do: Store.record_signal(signal, context)

  def record_prepared_llm_input(%{llm_call_id: call_id}, messages)
      when is_binary(call_id) and is_list(messages),
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

  defp truthy_observability_config(key, default) do
    case Application.get_env(:jido_murmur, :observability, []) |> Keyword.get(key, default) do
      false -> false
      _ -> true
    end
  end

  defp runtime_override(key), do: :persistent_term.get(key, :__unset__)
end
