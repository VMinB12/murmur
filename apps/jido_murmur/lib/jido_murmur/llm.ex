defmodule JidoMurmur.LLM do
  @moduledoc """
  Behaviour for the LLM interaction layer used by Runner.

  Implementations:
    - `JidoMurmur.LLM.Real` — production adapter (delegates to the Jido agent module)
    - `JidoMurmur.LLM.Mock` — test adapter with configurable canned responses
  """

  @type handle :: term()

  @callback ask(module(), pid(), String.t(), keyword()) :: {:ok, handle()} | {:error, term()}
  @callback await(module(), handle(), keyword()) :: {:ok, term()} | {:error, term()}
end
