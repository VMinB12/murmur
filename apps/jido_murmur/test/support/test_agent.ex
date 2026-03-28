defmodule JidoMurmur.TestAgent do
  @moduledoc "Minimal agent profile for jido_murmur tests."

  use Jido.AI.Agent,
    name: "test_agent",
    description: "A test agent for jido_murmur",
    model: :fast,
    tools: [],
    plugins: [],
    system_prompt: "You are a test agent."

  def catalog_meta, do: %{color: "blue"}
end
