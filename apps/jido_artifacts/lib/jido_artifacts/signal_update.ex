defmodule JidoArtifacts.SignalUpdate do
  @moduledoc """
  Typed artifact signal payload broadcast after plugin processing.
  """

  alias JidoArtifacts.Envelope

  @type mode :: :replace | :merge
  @type scope :: :agent | :workspace

  @type t :: %__MODULE__{
          name: String.t(),
          envelope: Envelope.t() | nil,
          mode: mode(),
          scope: scope()
        }

  @enforce_keys [:name, :envelope, :mode, :scope]
  defstruct [:name, :envelope, :mode, :scope]

  @spec new(String.t(), Envelope.t() | nil, keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(name, envelope, opts \\ []) do
    mode = Keyword.get(opts, :mode, :replace)
    scope = Keyword.get(opts, :scope, :agent)

    with :ok <- validate_name(name),
         :ok <- validate_envelope(envelope),
         :ok <- validate_mode(mode),
         :ok <- validate_scope(scope) do
      {:ok, %__MODULE__{name: name, envelope: envelope, mode: mode, scope: scope}}
    end
  end

  @spec new!(String.t(), Envelope.t() | nil, keyword()) :: t() | no_return()
  def new!(name, envelope, opts \\ []) do
    case new(name, envelope, opts) do
      {:ok, signal_update} -> signal_update
      {:error, reason} -> raise ArgumentError, "invalid artifact signal update: #{reason}"
    end
  end

  defp validate_name(name) when is_binary(name) and byte_size(name) > 0, do: :ok
  defp validate_name(_), do: {:error, "name must be a non-empty string"}

  defp validate_envelope(nil), do: :ok
  defp validate_envelope(%Envelope{}), do: :ok
  defp validate_envelope(_), do: {:error, "envelope must be nil or a JidoArtifacts.Envelope struct"}

  defp validate_mode(mode) when mode in [:replace, :merge], do: :ok
  defp validate_mode(_), do: {:error, "mode must be :replace or :merge"}

  defp validate_scope(scope) when scope in [:agent, :workspace], do: :ok
  defp validate_scope(_), do: {:error, "scope must be :agent or :workspace"}
end
