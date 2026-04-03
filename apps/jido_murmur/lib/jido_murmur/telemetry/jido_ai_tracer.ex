defmodule JidoMurmur.Telemetry.JidoAITracer do
  @moduledoc """
  Bridges Jido.AI runtime telemetry into Murmur's observability store.

  The upgraded ReAct runtime now emits request, LLM, and tool lifecycle
  telemetry under the canonical `[:jido, :ai, ...]` namespaces. Murmur uses
  those events to start and complete child spans while ReqLLM telemetry still
  provides the full payloads for message-oriented rendering.
  """

  require Logger

  alias JidoMurmur.Observability.Tracer

  @handler_id :jido_murmur_jido_ai_tracer

  @doc "Attaches telemetry handlers for Jido.AI runtime lifecycle events."
  def attach do
    events = [
      [:jido, :ai, :request, :start],
      [:jido, :ai, :request, :complete],
      [:jido, :ai, :request, :failed],
      [:jido, :ai, :request, :cancelled],
      [:jido, :ai, :llm, :start],
      [:jido, :ai, :llm, :complete],
      [:jido, :ai, :llm, :error],
      [:jido, :ai, :tool, :start],
      [:jido, :ai, :tool, :complete],
      [:jido, :ai, :tool, :error],
      [:jido, :ai, :tool, :timeout]
    ]

    :telemetry.attach_many(@handler_id, events, &__MODULE__.handle_event/4, %{})
    Logger.debug("JidoMurmur.Telemetry.JidoAITracer: Attached to [:jido, :ai, :*]")
  end

  @doc "Detaches the telemetry handler. Useful in tests."
  def detach do
    :telemetry.detach(@handler_id)
  end

  @doc false
  def handle_event([:jido, :ai, :llm, :start], _measurements, metadata, _config) do
    Tracer.span_start([:jido, :ai, :llm, :span], metadata)
    :ok
  rescue
    error ->
      Logger.warning("JidoAITracer llm start failed: #{inspect(error)}")
      :ok
  end

  def handle_event([:jido, :ai, :llm, :complete], measurements, metadata, _config) do
    Tracer.span_stop(%{kind: :llm, call_id: metadata[:llm_call_id]}, measurements)
    :ok
  rescue
    error ->
      Logger.warning("JidoAITracer llm complete failed: #{inspect(error)}")
      :ok
  end

  def handle_event([:jido, :ai, :llm, :error], _measurements, metadata, _config) do
    reason = metadata[:reason] || metadata[:error] || metadata[:exception] || :llm_error
    Tracer.span_exception(%{kind: :llm, call_id: metadata[:llm_call_id]}, :error, reason, [])
    :ok
  rescue
    error ->
      Logger.warning("JidoAITracer llm error failed: #{inspect(error)}")
      :ok
  end

  def handle_event([:jido, :ai, :tool, :start], _measurements, metadata, _config) do
    Tracer.span_start([:jido, :ai, :tool, :span], metadata)
    :ok
  rescue
    error ->
      Logger.warning("JidoAITracer tool start failed: #{inspect(error)}")
      :ok
  end

  def handle_event([:jido, :ai, :tool, :complete], measurements, metadata, _config) do
    Tracer.span_stop(%{kind: :tool, call_id: metadata[:tool_call_id]}, measurements)
    :ok
  rescue
    error ->
      Logger.warning("JidoAITracer tool complete failed: #{inspect(error)}")
      :ok
  end

  def handle_event([:jido, :ai, :tool, :error], _measurements, metadata, _config) do
    reason = metadata[:reason] || metadata[:error] || metadata[:exception] || :tool_error
    Tracer.span_exception(%{kind: :tool, call_id: metadata[:tool_call_id]}, :error, reason, [])
    :ok
  rescue
    error ->
      Logger.warning("JidoAITracer tool error failed: #{inspect(error)}")
      :ok
  end

  def handle_event([:jido, :ai, :tool, :timeout], _measurements, metadata, _config) do
    Tracer.span_exception(%{kind: :tool, call_id: metadata[:tool_call_id]}, :timeout, :tool_timeout, [])
    :ok
  rescue
    error ->
      Logger.warning("JidoAITracer tool timeout failed: #{inspect(error)}")
      :ok
  end

  def handle_event([:jido, :ai, :request, _event], _measurements, _metadata, _config), do: :ok
  def handle_event(_event, _measurements, _metadata, _config), do: :ok
end
