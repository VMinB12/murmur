defmodule Murmur.Agents.Telemetry do
  @moduledoc """
  Helpers for attaching/detaching telemetry handlers that forward
  Jido AI LLM delta events to a LiveView process for streaming display.
  """

  require Logger

  @delta_event [:jido, :ai, :llm, :delta]

  @doc """
  Attach a telemetry handler that forwards LLM delta events to the given pid.
  The handler_id is scoped to the session_id so it can be detached later.
  """
  def attach(pid, session_id) do
    handler_id = handler_id(session_id)

    :telemetry.attach(
      handler_id,
      @delta_event,
      &handle_delta/4,
      %{pid: pid, session_id: session_id}
    )

    handler_id
  end

  @doc """
  Detach the telemetry handler for the given session_id.
  """
  def detach(session_id) do
    :telemetry.detach(handler_id(session_id))
  rescue
    e ->
      Logger.warning("Failed to detach telemetry handler for #{session_id}: #{Exception.message(e)}")

      :ok
  end

  defp handler_id(session_id), do: "murmur_delta_#{session_id}"

  defp handle_delta(_event, _measurements, _metadata, %{pid: pid, session_id: session_id}) do
    if Process.alive?(pid) do
      send(pid, {:streaming_active, session_id})
    end
  end
end
