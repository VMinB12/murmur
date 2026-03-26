defmodule Murmur.Agents.LLM do
  @moduledoc """
  Behaviour for the LLM interaction layer used by Runner.

  In production, delegates to the actual Jido.AI.Agent module's ask/await.
  In tests, can be replaced with a Mox mock to avoid real API calls.
  """

  @type handle :: term()

  @callback ask(module(), pid(), String.t(), map()) ::
              {:ok, handle()} | {:error, term()}

  @callback await(module(), handle(), keyword()) ::
              {:ok, term()} | {:error, term()}
end
