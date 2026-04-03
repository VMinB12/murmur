defmodule JidoMurmur.Observability.Tracer do
  @moduledoc """
  `Jido.Observe.Tracer` implementation for Murmur-owned LLM and tool spans.
  """

  @behaviour Jido.Observe.Tracer

  alias JidoMurmur.Observability
  alias JidoMurmur.Observability.Store

  @impl true
  def span_start([:jido, :ai, :llm, :span], metadata) do
    llm_call_id = metadata[:llm_call_id]

    if is_binary(llm_call_id) do
      Observability.set_active_llm_call_id(llm_call_id)
    end

    Store.start_llm_span(metadata)
  end

  def span_start([:jido, :ai, :tool, :span], metadata) do
    Store.start_tool_span(metadata)
  end

  def span_start(_event_prefix, _metadata), do: nil

  @impl true
  def span_stop(nil, _measurements), do: :ok

  def span_stop(%{kind: :llm, call_id: call_id}, measurements) do
    Observability.clear_active_llm_call_id()
    Store.mark_llm_span_complete(call_id, measurements)
  end

  def span_stop(%{kind: :tool, call_id: call_id}, measurements) do
    Store.mark_tool_span_complete(call_id, measurements)
  end

  def span_stop(_ctx, _measurements), do: :ok

  @impl true
  def span_exception(nil, _kind, _reason, _stacktrace), do: :ok

  def span_exception(%{kind: :llm, call_id: call_id}, kind, reason, _stacktrace) do
    Observability.clear_active_llm_call_id()
    Store.mark_llm_span_error(call_id, kind, reason)
  end

  def span_exception(%{kind: :tool, call_id: call_id}, kind, reason, _stacktrace) do
    Store.mark_tool_span_error(call_id, kind, reason)
  end

  def span_exception(_ctx, _kind, _reason, _stacktrace), do: :ok
end
