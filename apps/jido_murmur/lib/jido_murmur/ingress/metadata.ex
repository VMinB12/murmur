defmodule JidoMurmur.Ingress.Metadata do
  @moduledoc """
  Canonical Murmur routing and observability metadata carried inside ingress refs.

  Known fields are projected into a structured form once and preserved as
  atom-keyed refs for downstream runtime use.
  """

    alias JidoMurmur.ActorIdentity

  @enforce_keys [:interaction_id, :workspace_id]
    defstruct [:interaction_id, :workspace_id, :sender_name, :origin_actor, :sender_trace_id, hop_count: 0, extra: %{}]

    @known_keys [:interaction_id, :workspace_id, :sender_name, :origin_actor, :sender_trace_id, :hop_count]

  @type t :: %__MODULE__{
          interaction_id: String.t(),
          workspace_id: String.t(),
          sender_name: String.t() | nil,
      origin_actor: ActorIdentity.t() | nil,
          sender_trace_id: String.t() | nil,
          hop_count: non_neg_integer(),
          extra: map()
        }

  @type validation_error ::
          :invalid_refs
          | :missing_interaction_id
          | :invalid_interaction_id
          | :missing_workspace_id
          | :invalid_workspace_id
          | :invalid_sender_name
          | :invalid_origin_actor
          | :invalid_sender_trace_id
          | :invalid_hop_count

  @spec new(map()) :: {:ok, t()} | {:error, validation_error()}
  def new(%{} = refs) do
    sender_name = Map.get(refs, :sender_name)

    with :ok <- validate_atom_keys(refs),
         :ok <- validate_required_binary(Map.get(refs, :interaction_id), :missing_interaction_id, :invalid_interaction_id),
         :ok <- validate_required_binary(Map.get(refs, :workspace_id), :missing_workspace_id, :invalid_workspace_id),
         :ok <- validate_optional_binary(sender_name, :invalid_sender_name),
         {:ok, origin_actor} <- normalize_origin_actor(Map.get(refs, :origin_actor), sender_name),
         :ok <- validate_optional_binary(Map.get(refs, :sender_trace_id), :invalid_sender_trace_id),
         {:ok, hop_count} <- normalize_hop_count(Map.get(refs, :hop_count, 0)) do
      {:ok,
       %__MODULE__{
         interaction_id: Map.fetch!(refs, :interaction_id),
         workspace_id: Map.fetch!(refs, :workspace_id),
         sender_name: sender_name || ActorIdentity.display_name(origin_actor),
         origin_actor: origin_actor,
         sender_trace_id: Map.get(refs, :sender_trace_id),
         hop_count: hop_count,
         extra: Map.drop(refs, @known_keys)
       }}
    end
  end

  def new(_), do: {:error, :invalid_refs}

  @spec to_refs(t()) :: map()
  def to_refs(%__MODULE__{} = metadata) do
    canonical_refs =
      %{
        interaction_id: metadata.interaction_id,
        workspace_id: metadata.workspace_id,
        sender_name: metadata.sender_name,
        origin_actor: ActorIdentity.serialize(metadata.origin_actor),
        sender_trace_id: metadata.sender_trace_id,
        hop_count: metadata.hop_count
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Map.merge(metadata.extra, canonical_refs)
  end

  @spec tool_context(t(), ActorIdentity.t(), String.t()) :: map()
  def tool_context(%__MODULE__{} = metadata, %ActorIdentity{} = current_actor, request_id)
      when is_binary(request_id) do
    %{
      workspace_id: metadata.workspace_id,
      current_actor: current_actor,
      sender_name: ActorIdentity.display_name(current_actor),
      interaction_id: metadata.interaction_id,
      request_id: request_id,
      hop_count: metadata.hop_count
    }
    |> maybe_put(:sender_trace_id, metadata.sender_trace_id)
    |> maybe_put(:origin_actor, metadata.origin_actor)
    |> maybe_put(:origin_sender_name, ActorIdentity.display_name(metadata.origin_actor) || metadata.sender_name)
  end

  defp validate_atom_keys(refs) do
    if Enum.all?(Map.keys(refs), &is_atom/1) do
      :ok
    else
      {:error, :invalid_refs}
    end
  end

  defp validate_required_binary(nil, missing_error, _invalid_error), do: {:error, missing_error}
  defp validate_required_binary(value, _missing_error, _invalid_error) when is_binary(value), do: :ok
  defp validate_required_binary(_value, _missing_error, invalid_error), do: {:error, invalid_error}

  defp validate_optional_binary(nil, _error), do: :ok
  defp validate_optional_binary(value, _error) when is_binary(value), do: :ok
  defp validate_optional_binary(_value, error), do: {:error, error}

  defp normalize_origin_actor(nil, nil), do: {:ok, nil}

  defp normalize_origin_actor(nil, sender_name) when is_binary(sender_name) do
    {:ok, ActorIdentity.unknown(sender_name)}
  end

  defp normalize_origin_actor(nil, _sender_name), do: {:ok, nil}

  defp normalize_origin_actor(origin_actor, _sender_name) do
    case ActorIdentity.normalize(origin_actor) do
      {:ok, normalized} -> {:ok, normalized}
      {:error, _reason} -> {:error, :invalid_origin_actor}
    end
  end

  defp normalize_hop_count(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp normalize_hop_count(_value), do: {:error, :invalid_hop_count}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
