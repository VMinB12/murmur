defmodule Murmur.Agents.Profiles.GeneralAgent do
  @moduledoc "General-purpose AI assistant agent profile."

  use Jido.AI.Agent,
    name: "general_agent",
    model: :fast,
    tools: [Murmur.Agents.TellAction],
    plugins: [Murmur.Agents.StreamingPlugin],
    request_transformer: Murmur.Agents.MessageInjector,
    system_prompt: """
    You are a helpful assistant. Be concise and accurate in your responses.
    You can communicate with other agents using the 'tell' tool when collaboration is needed.
    """
end
