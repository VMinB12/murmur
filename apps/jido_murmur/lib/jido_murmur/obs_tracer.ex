defmodule JidoMurmur.ObsTracer do
  @moduledoc """
  Custom `Jido.Observe.Tracer` wrapper over `AgentObs.JidoTracer`.

  Enriches every span with workspace and agent identity metadata before
  delegating to AgentObs, enabling:

  - **Phoenix Sessions grouping** via `session_id` = workspace UUID
  - **Agent identity** via `agent_name` and tags
  - **Cross-agent causation** via `triggered_by_agent` / `triggered_by_trace_id`
  """

  @behaviour Jido.Observe.Tracer

  alias JidoMurmur.ObsTracer.Cache

  @impl true
  def span_start(event_prefix, metadata) do
    enriched =
      metadata
      |> put_session_id()
      |> put_agent_identity()

    AgentObs.JidoTracer.span_start(event_prefix, enriched)
  end

  @impl true
  def span_stop(span_ctx, measurements) do
    AgentObs.JidoTracer.span_stop(span_ctx, measurements)
  end

  @impl true
  def span_exception(span_ctx, kind, reason, stacktrace) do
    AgentObs.JidoTracer.span_exception(span_ctx, kind, reason, stacktrace)
  end

  # --- Enrichment ---

  defp put_session_id(metadata) do
    case lookup_workspace_id(metadata[:agent_id]) do
      nil -> metadata
      workspace_id -> Map.put(metadata, :session_id, workspace_id)
    end
  end

  defp put_agent_identity(metadata) do
    case lookup_display_name(metadata[:agent_id]) do
      nil ->
        metadata

      name ->
        metadata
        |> Map.put(:agent_name, name)
        |> Map.update(:tags, ["agent:#{name}"], &["agent:#{name}" | &1])
    end
  end

  defp lookup_workspace_id(nil), do: nil

  defp lookup_workspace_id(agent_id) do
    case Cache.lookup(agent_id) do
      {workspace_id, _display_name} -> workspace_id
      nil -> nil
    end
  end

  defp lookup_display_name(nil), do: nil

  defp lookup_display_name(agent_id) do
    case Cache.lookup(agent_id) do
      {_workspace_id, display_name} -> display_name
      nil -> nil
    end
  end
end
