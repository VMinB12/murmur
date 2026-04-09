defmodule JidoMurmur.StreamingPlugin do
  @moduledoc """
  Jido Plugin that intercepts lifecycle signals emitted by the ReAct
  strategy and reduces them into Murmur-owned canonical conversation updates.

  Raw `ai.*` lifecycle facts remain internal projector inputs and observability
  events. Chat surfaces subscribe to canonical Murmur-owned signals instead of
  the raw lifecycle transport.
  """

  use Jido.Plugin,
    name: "streaming",
    state_key: :streaming,
    actions: [],
    signal_patterns: [
      "ai.llm.delta",
      "ai.llm.response",
      "ai.tool.started",
      "ai.tool.result",
      "ai.request.started",
      "ai.request.completed",
      "ai.request.failed",
      "ai.usage"
    ]

  alias JidoMurmur.Observability
  alias JidoMurmur.Runner

  @impl Jido.Plugin
  def handle_signal(signal, context) do
    session_id = context.agent.id
    workspace_id = context.agent.state[:workspace_id]

    :telemetry.execute(
      [:jido_murmur, :streaming, :signal],
      %{system_time: System.system_time()},
      %{session_id: session_id, signal_type: signal.type}
    )

    # Set subject on the signal if not already set, then broadcast directly
    signal =
      if signal.subject do
        signal
      else
        %{signal | subject: "/agents/#{session_id}"}
      end

    signal = maybe_attach_request_id(signal, session_id)

    _ = JidoMurmur.ConversationProjector.apply_signal(workspace_id, session_id, context.agent, signal)

    Observability.record_signal(signal, %{workspace_id: workspace_id, session_id: session_id})
    {:ok, :continue}
  end

  defp maybe_attach_request_id(%Jido.Signal{data: data} = signal, _session_id) when not is_map(data), do: signal

  defp maybe_attach_request_id(%Jido.Signal{data: data} = signal, session_id) do
    request_id = Map.get(data, :request_id) || Map.get(data, "request_id") || Runner.active_request_id(session_id)

    if is_binary(request_id) do
      %{signal | data: Map.put(data, :request_id, request_id)}
    else
      signal
    end
  end
end
