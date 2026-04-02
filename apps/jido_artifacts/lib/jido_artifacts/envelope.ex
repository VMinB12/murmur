defmodule JidoArtifacts.Envelope do
  @moduledoc """
  Canonical in-memory artifact contract.

  Murmur persists this struct directly in agent checkpoints via
  `:erlang.term_to_binary`, so all live and persisted artifact paths should use
  the same shape.
  """

  @enforce_keys [:data, :version, :source, :updated_at]
  defstruct [:data, :version, :source, :updated_at]

  @type t :: %__MODULE__{
          data: term(),
          version: pos_integer(),
          source: String.t(),
          updated_at: DateTime.t()
        }

  @spec new(term(), pos_integer(), String.t(), DateTime.t()) :: t()
  def new(data, version, source, updated_at \\ DateTime.utc_now())

  def new(data, version, source, %DateTime{} = updated_at)
      when is_integer(version) and version > 0 and is_binary(source) do
    %__MODULE__{data: data, version: version, source: source, updated_at: updated_at}
  end

  @spec next(t() | nil, term(), String.t(), DateTime.t()) :: t()
  def next(existing_envelope, data, source, updated_at \\ DateTime.utc_now())

  def next(%__MODULE__{version: version}, data, source, %DateTime{} = updated_at) do
    new(data, version + 1, source, updated_at)
  end

  def next(nil, data, source, %DateTime{} = updated_at) do
    new(data, 1, source, updated_at)
  end

  @spec data(t()) :: term()
  def data(%__MODULE__{data: data}), do: data

  @spec version(t()) :: pos_integer()
  def version(%__MODULE__{version: version}), do: version
end
