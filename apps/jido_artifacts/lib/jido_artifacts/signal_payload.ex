defmodule JidoArtifacts.SignalPayload do
  @moduledoc """
  Typed artifact signal payload emitted by tool actions before plugin processing.
  """

  @type mode :: :replace | :merge
  @type scope :: :agent | :workspace

  @type t :: %__MODULE__{
          name: String.t(),
          payload: term(),
          mode: mode(),
          merge_result: term() | nil,
          scope: scope()
        }

  @enforce_keys [:name, :payload, :mode, :scope]
  defstruct [:name, :payload, :mode, :merge_result, :scope]

  @spec new(String.t(), term(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(name, payload, opts \\ []) do
    mode = Keyword.get(opts, :mode, :replace)
    scope = Keyword.get(opts, :scope, :agent)
    merge_result = Keyword.get(opts, :merge_result)

    with :ok <- validate_name(name),
         :ok <- validate_mode(mode),
         :ok <- validate_scope(scope) do
      {:ok,
       %__MODULE__{
         name: name,
         payload: payload,
         mode: mode,
         merge_result: merge_result,
         scope: scope
       }}
    end
  end

  @spec new!(String.t(), term(), keyword()) :: t() | no_return()
  def new!(name, payload, opts \\ []) do
    case new(name, payload, opts) do
      {:ok, signal_payload} -> signal_payload
      {:error, reason} -> raise ArgumentError, "invalid artifact signal payload: #{reason}"
    end
  end

  defp validate_name(name) when is_binary(name) and byte_size(name) > 0, do: :ok
  defp validate_name(_), do: {:error, "name must be a non-empty string"}

  defp validate_mode(mode) when mode in [:replace, :merge], do: :ok
  defp validate_mode(_), do: {:error, "mode must be :replace or :merge"}

  defp validate_scope(scope) when scope in [:agent, :workspace], do: :ok
  defp validate_scope(_), do: {:error, "scope must be :agent or :workspace"}
end
