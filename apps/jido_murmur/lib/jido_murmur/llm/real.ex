defmodule JidoMurmur.LLM.Real do
  @moduledoc "Production LLM adapter — delegates to the actual agent module."
  @behaviour JidoMurmur.LLM

  @impl true
  def ask(agent_module, pid, content, opts) do
    agent_module.ask(pid, content, opts)
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def steer(agent_module, pid, content, opts) do
    agent_module.steer(pid, content, opts)
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def inject(agent_module, pid, content, opts) do
    agent_module.inject(pid, content, opts)
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
