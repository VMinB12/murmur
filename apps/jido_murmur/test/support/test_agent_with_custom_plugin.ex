defmodule JidoMurmur.TestAgentWithCustomPlugin do
  @moduledoc """
  Test agent that configures both package plugins and a custom plugin.

  Used to validate that custom Jido.Plugin implementations
  work alongside JidoMurmur's StreamingPlugin and ArtifactPlugin.
  """

  use Jido.AI.Agent,
    name: "test_agent_with_custom_plugin",
    description: "Test agent with custom plugin",
    model: :fast,
    tools: [],
    plugins: [
      JidoMurmur.StreamingPlugin,
      JidoArtifacts.ArtifactPlugin,
      JidoMurmur.TestCustomPlugin
    ],
    system_prompt: "You are a test agent with custom plugins."

  def catalog_meta, do: %{color: "emerald"}
end
