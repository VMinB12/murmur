defmodule JidoMurmur.DisplayMessage.ToolCall do
  @moduledoc false

  defstruct [:id, :name, :args, :result, :status]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          args: term(),
          result: String.t() | nil,
          status: :running | :completed | :error | nil
        }
end
