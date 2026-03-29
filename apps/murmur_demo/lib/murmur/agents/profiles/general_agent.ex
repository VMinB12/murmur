defmodule Murmur.Agents.Profiles.GeneralAgent do
  @moduledoc "General-purpose AI assistant agent profile."
  @behaviour JidoMurmur.AgentProfile

  use Jido.AI.Agent,
    name: "general_agent",
    description: "A helpful general-purpose assistant",
    model: :fast,
    tools: [
      JidoMurmur.TellAction,
      JidoTasks.Tools.AddTask,
      JidoTasks.Tools.UpdateTask,
      JidoTasks.Tools.ListTasks
    ],
    plugins: [JidoMurmur.StreamingPlugin, JidoArtifacts.ArtifactPlugin],
    request_transformer: JidoMurmur.MessageInjector,
    system_prompt: """
    You are a helpful assistant. Be concise and accurate in your responses.
    """

  @impl JidoMurmur.AgentProfile
  def catalog_meta, do: %{color: "blue"}
end
