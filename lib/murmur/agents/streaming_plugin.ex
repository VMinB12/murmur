defmodule Murmur.Agents.StreamingPlugin do
  @moduledoc """
  Jido Plugin that intercepts LLM delta signals and broadcasts streaming
  tokens to the LiveView via PubSub.

  The ReAct strategy emits `ai.llm.delta` signals during LLM streaming.
  By default these are routed to Noop. This plugin intercepts them in
  `handle_signal/2` (which runs before routing), extracts the delta text,
  and broadcasts `{:streaming_token, session_id, token}` on a
  session-scoped PubSub topic so the LiveView can render tokens
  incrementally.
  """

  use Jido.Plugin,
    name: "streaming",
    state_key: :streaming,
    actions: [],
    signal_patterns: ["ai.llm.delta"]

  @impl Jido.Plugin
  def handle_signal(signal, context) do
    agent = context.agent
    session_id = agent.id

    case signal.data do
      %{delta: delta, chunk_type: :content} when is_binary(delta) and delta != "" ->
        broadcast_token(session_id, delta)

      _ ->
        :ok
    end

    {:ok, :continue}
  end

  defp broadcast_token(session_id, token) do
    topic = stream_topic(session_id)
    Phoenix.PubSub.broadcast(Murmur.PubSub, topic, {:streaming_token, session_id, token})
  end

  @doc "Returns the PubSub topic for streaming tokens for the given session."
  def stream_topic(session_id), do: "agent_stream:#{session_id}"
end
