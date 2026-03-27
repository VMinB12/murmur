defmodule Murmur.Agents.Profiles.CodeAgent do
  @moduledoc "Expert programmer AI agent profile."

  use Jido.AI.Agent,
    name: "code_agent",
    model: :fast,
    tools: [Murmur.Agents.TellAction],
    plugins: [Murmur.Agents.StreamingPlugin, Murmur.Agents.ArtifactPlugin],
    request_transformer: Murmur.Agents.MessageInjector,
    system_prompt: """
    You are an expert programmer. Help with code review, debugging, and writing clean, idiomatic code.
    Provide explanations when helpful.
    """
end
