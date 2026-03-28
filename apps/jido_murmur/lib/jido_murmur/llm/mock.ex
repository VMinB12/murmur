defmodule JidoMurmur.LLM.Mock do
  @moduledoc """
  Test LLM adapter with configurable canned responses.

  ## Usage

      # Set up a custom response for the current test process
      JidoMurmur.LLM.Mock.set_response(%{content: "Hello from mock!"})

      # The mock will return it on next await/3 call
  """
  @behaviour JidoMurmur.LLM

  @default_response %{content: "Mock LLM response"}

  @impl true
  def ask(_agent_module, _pid, _content, _opts) do
    {:ok, make_ref()}
  end

  @impl true
  def await(_agent_module, _handle, _opts) do
    response = Process.get(:mock_llm_response, @default_response)
    {:ok, response}
  end

  @doc "Set the mock response for the current process."
  def set_response(response) do
    Process.put(:mock_llm_response, response)
    :ok
  end
end
