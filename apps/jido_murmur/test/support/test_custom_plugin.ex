defmodule JidoMurmur.TestCustomPlugin do
  @moduledoc """
  A custom Jido.Plugin for testing interplay with package plugins.

  Broadcasts signals to a custom PubSub topic to verify that both
  package plugins (StreamingPlugin, ArtifactPlugin) and custom
  plugins receive and process signals without interference.
  """

  use Jido.Plugin,
    name: "test_custom",
    state_key: :test_custom,
    actions: [],
    signal_patterns: ["ai.llm.response", "ai.request.completed"]

  @impl Jido.Plugin
  def handle_signal(signal, context) do
    session_id = context.agent.id
    topic = "custom_plugin:#{session_id}"

    Phoenix.PubSub.broadcast(
      JidoMurmur.pubsub(),
      topic,
      {:custom_plugin_signal, session_id, signal}
    )

    {:ok, :continue}
  end
end
