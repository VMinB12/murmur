defmodule Murmur.Agents.LLM.Real do
  @moduledoc "Production LLM adapter — delegates to the actual agent module."

  @behaviour Murmur.Agents.LLM

  @impl true
  def ask(agent_module, pid, content, tool_ctx) do
    agent_module.ask(pid, content, tool_context: tool_ctx)
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def await(agent_module, req, opts) do
    agent_module.await(req, opts)
  rescue
    e -> {:error, Exception.message(e)}
  end
end
