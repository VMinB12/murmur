defmodule JidoMurmur.ActorIdentity do
  @moduledoc """
  Explicit actor identity semantics shared across runtime and UI boundaries.
  """

  @enforce_keys [:kind]
  defstruct [:kind, :name, :id]

  @type kind :: :agent | :human | :programmatic | :system | :unknown

  @type t :: %__MODULE__{
          kind: kind(),
          name: String.t() | nil,
          id: String.t() | nil
        }

  @type validation_error :: :invalid_actor_identity

  @spec agent(String.t(), keyword()) :: t()
  def agent(name, opts \\ []) when is_binary(name), do: build(:agent, name, opts)

  @spec human(String.t() | nil, keyword()) :: t()
  def human(name \\ nil, opts \\ []), do: build(:human, name, opts)

  @spec programmatic(String.t() | nil, keyword()) :: t()
  def programmatic(name \\ nil, opts \\ []), do: build(:programmatic, name, opts)

  @spec system(String.t() | nil, keyword()) :: t()
  def system(name \\ nil, opts \\ []), do: build(:system, name, opts)

  @spec unknown(String.t() | nil, keyword()) :: t()
  def unknown(name \\ nil, opts \\ []), do: build(:unknown, name, opts)

  @spec normalize(term()) :: {:ok, t() | nil} | {:error, validation_error()}
  def normalize(nil), do: {:ok, nil}

  def normalize(%__MODULE__{} = actor) do
    with {:ok, _kind} <- normalize_kind(actor.kind),
         :ok <- validate_optional_binary(actor.name),
         :ok <- validate_optional_binary(actor.id) do
      {:ok, actor}
    else
      _ -> {:error, :invalid_actor_identity}
    end
  end

  def normalize(%{} = actor) do
    name = Map.get(actor, :name) || Map.get(actor, "name")
    id = Map.get(actor, :id) || Map.get(actor, "id")

    with {:ok, kind} <- normalize_kind(Map.get(actor, :kind) || Map.get(actor, "kind")),
         :ok <- validate_optional_binary(name),
         :ok <- validate_optional_binary(id) do
      {:ok, %__MODULE__{kind: kind, name: name, id: id}}
    else
      _ -> {:error, :invalid_actor_identity}
    end
  end

  def normalize(_), do: {:error, :invalid_actor_identity}

  @spec from_source(map(), String.t() | nil) :: t() | nil
  def from_source(%{kind: kind}, sender_name), do: from_kind(kind, sender_name)
  def from_source(_source, sender_name) when is_binary(sender_name), do: unknown(sender_name)
  def from_source(_source, _sender_name), do: nil

  @spec serialize(t() | nil) :: map() | nil
  def serialize(nil), do: nil

  def serialize(%__MODULE__{} = actor) do
    %{kind: actor.kind}
    |> maybe_put(:name, actor.name)
    |> maybe_put(:id, actor.id)
  end

  @spec display_name(t() | nil) :: String.t() | nil
  def display_name(nil), do: nil
  def display_name(%__MODULE__{} = actor), do: actor.name

  defp from_kind(:human, sender_name), do: human(sender_name)
  defp from_kind("human", sender_name), do: human(sender_name)
  defp from_kind(:programmatic, sender_name) when is_binary(sender_name), do: programmatic(sender_name)
  defp from_kind("programmatic", sender_name) when is_binary(sender_name), do: programmatic(sender_name)
  defp from_kind(:programmatic, _sender_name), do: programmatic()
  defp from_kind("programmatic", _sender_name), do: programmatic()
  defp from_kind(:system, sender_name), do: system(sender_name)
  defp from_kind("system", sender_name), do: system(sender_name)
  defp from_kind(_kind, sender_name) when is_binary(sender_name), do: unknown(sender_name)
  defp from_kind(_kind, _sender_name), do: nil

  defp build(kind, name, opts) do
    %__MODULE__{kind: kind, name: name, id: Keyword.get(opts, :id)}
  end

  defp normalize_kind(kind) when kind in [:agent, :human, :programmatic, :system, :unknown],
    do: {:ok, kind}

  defp normalize_kind(kind) when is_binary(kind) do
    case kind do
      "agent" -> {:ok, :agent}
      "human" -> {:ok, :human}
      "programmatic" -> {:ok, :programmatic}
      "system" -> {:ok, :system}
      "unknown" -> {:ok, :unknown}
      _ -> {:error, :invalid_actor_identity}
    end
  end

  defp normalize_kind(_kind), do: {:error, :invalid_actor_identity}

  defp validate_optional_binary(nil), do: :ok
  defp validate_optional_binary(value) when is_binary(value), do: :ok
  defp validate_optional_binary(_value), do: {:error, :invalid_actor_identity}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

end
