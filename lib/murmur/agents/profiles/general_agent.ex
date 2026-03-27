defmodule Murmur.Agents.Profiles.GeneralAgent do
  @moduledoc "General-purpose AI assistant agent profile."

  use Jido.AI.Agent,
    name: "general_agent",
    description: "A helpful general-purpose assistant",
    model: :fast,
    tools: [
      Murmur.Agents.TellAction,
      Murmur.Agents.Tools.AddTask,
      Murmur.Agents.Tools.UpdateTask,
      Murmur.Agents.Tools.ListTasks
    ],
    plugins: [Murmur.Agents.StreamingPlugin, Murmur.Agents.ArtifactPlugin],
    request_transformer: Murmur.Agents.MessageInjector,
    system_prompt: """
    You are a helpful assistant. Be concise and accurate in your responses.
    """

  def catalog_meta, do: %{color: "blue"}
end
