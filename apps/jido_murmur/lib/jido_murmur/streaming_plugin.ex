defmodule JidoMurmur.StreamingPlugin do
  @moduledoc """
  Jido Plugin that intercepts lifecycle signals emitted by the ReAct
  strategy and forwards them to the LiveView via PubSub.

  All matched signals are broadcast as `{:agent_signal, session_id, signal}`
  on a session-scoped PubSub topic. The LiveView pattern-matches on the
  signal type to decide what to render.
  """

  use Jido.Plugin,
    name: "streaming",
    state_key: :streaming,
    actions: [],
    signal_patterns: [
      "ai.llm.delta",
      "ai.llm.response",
      "ai.tool.result",
      "ai.request.started",
      "ai.request.completed",
      "ai.request.failed",
      "ai.usage"
    ]

  @impl Jido.Plugin
  def handle_signal(signal, context) do
    session_id = context.agent.id
    topic = stream_topic(session_id)

    :telemetry.execute(
      [:jido_murmur, :streaming, :signal],
      %{system_time: System.system_time()},
      %{session_id: session_id, signal_type: signal.type}
    )

    Phoenix.PubSub.broadcast(JidoMurmur.pubsub(), topic, {:agent_signal, session_id, signal})
    {:ok, :continue}
  end

  @doc "Returns the PubSub topic for agent signals for the given session."
  def stream_topic(session_id), do: "agent_stream:#{session_id}"
end
