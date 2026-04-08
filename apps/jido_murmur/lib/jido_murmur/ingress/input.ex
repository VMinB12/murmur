defmodule JidoMurmur.Ingress.Input do
  @moduledoc """
  Canonical ingress input aligned with `jido_ai` control payloads.

  Murmur-specific routing and observability metadata lives inside `refs`.
  Use the explicit builder functions for Murmur-owned producer paths and
  `new/2` only when constructing canonical input directly.
  """

  alias JidoMurmur.ActorIdentity
  alias JidoMurmur.Ingress.Metadata

  @enforce_keys [:content]
  defstruct [:content, :source, refs: %{}, expected_request_id: nil]

  @type t :: %__MODULE__{
          content: String.t(),
          source: term(),
          refs: map(),
          expected_request_id: String.t() | nil
        }

  @type validation_error ::
          :empty_content
          | :missing_source
          | :invalid_source
          | :invalid_refs
          | :missing_workspace_id
          | :invalid_workspace_id
          | :invalid_sender_name
          | :invalid_origin_actor
          | :invalid_sender_trace_id
          | :invalid_hop_count
          | :invalid_expected_request_id

  @type session_like :: %{
          required(:id) => String.t(),
          required(:workspace_id) => String.t(),
          optional(atom()) => any()
        }

  @spec new(String.t(), list()) :: {:ok, t()} | {:error, validation_error()}
  def new(content, opts \\ []) when is_binary(content) and is_list(opts) do
    normalized_content = String.trim(content)

    with :ok <- validate_content(normalized_content),
         {:ok, normalized_source} <- normalize_source(Keyword.get(opts, :source)),
         {:ok, normalized_refs} <- normalize_refs(Keyword.get(opts, :refs, %{})),
         {:ok, normalized_request_id} <- normalize_request_id(Keyword.get(opts, :expected_request_id)) do
      {:ok,
       %__MODULE__{
         content: normalized_content,
         source: normalized_source,
         refs: normalized_refs,
         expected_request_id: normalized_request_id
       }}
    end
  end

  @spec direct_message(session_like(), String.t(), list()) :: {:ok, t()} | {:error, validation_error()}
  def direct_message(session, content, opts \\ []) when is_list(opts) do
    with {:ok, extra_refs} <- normalize_extra_refs(Keyword.get(opts, :refs, %{})) do
      new(content,
        source: %{kind: :human, via: Keyword.get(opts, :via, :workspace_live)},
        refs:
          Map.merge(extra_refs, %{
            workspace_id: session.workspace_id,
            origin_actor: ActorIdentity.serialize(ActorIdentity.human())
          })
      )
    end
  end

  @spec programmatic_message(session_like(), String.t(), list()) ::
          {:ok, t()} | {:error, validation_error()}
  def programmatic_message(session, content, opts \\ []) when is_list(opts) do
    with {:ok, via} <- normalize_via(Keyword.get(opts, :via)),
         {:ok, extra_refs} <- normalize_extra_refs(Keyword.get(opts, :refs, %{})),
         {:ok, origin_actor} <- normalize_origin_actor(Keyword.get(opts, :origin_actor), Keyword.get(opts, :sender_name)) do
      refs =
        extra_refs
        |> Map.merge(%{
          sender_name: Keyword.get(opts, :sender_name) || ActorIdentity.display_name(origin_actor),
          origin_actor: ActorIdentity.serialize(origin_actor),
          sender_trace_id: Keyword.get(opts, :sender_trace_id),
          workspace_id: session.workspace_id
        })
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      new(content,
        source: %{kind: :programmatic, via: via},
        refs: refs,
        expected_request_id: Keyword.get(opts, :expected_request_id)
      )
    end
  end

  @spec control_kind(t()) :: :steer | :inject
  def control_kind(%__MODULE__{source: %{kind: :human}}), do: :steer
  def control_kind(%__MODULE__{source: %{kind: "human"}}), do: :steer
  def control_kind(_input), do: :inject

  @spec validate(t()) :: :ok | {:error, validation_error()}
  def validate(%__MODULE__{} = input) do
    with :ok <- validate_content(input.content),
         {:ok, _source} <- normalize_source(input.source),
         {:ok, _refs} <- normalize_refs(input.refs),
         {:ok, _request_id} <- normalize_request_id(input.expected_request_id) do
      :ok
    end
  end

  @spec metadata(t()) :: {:ok, Metadata.t()} | {:error, validation_error()}
  def metadata(%__MODULE__{refs: refs}), do: Metadata.new(refs)

  defp validate_content(""), do: {:error, :empty_content}
  defp validate_content(content) when is_binary(content), do: :ok

  defp normalize_source(nil), do: {:error, :missing_source}
  defp normalize_source(%{} = source), do: validate_source_map(source)
  defp normalize_source(_), do: {:error, :invalid_source}

  defp validate_source_map(%{kind: kind, via: via} = source)
       when (is_atom(kind) or is_binary(kind)) and (is_atom(via) or is_binary(via)) do
    {:ok, source}
  end

  defp validate_source_map(_source), do: {:error, :invalid_source}

  defp normalize_via(value) when is_atom(value) or is_binary(value), do: {:ok, value}
  defp normalize_via(_value), do: {:error, :invalid_source}

  defp normalize_refs(%{} = refs) do
    case Metadata.new(refs) do
      {:ok, metadata} -> {:ok, Metadata.to_refs(metadata)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_refs(_), do: {:error, :invalid_refs}

  defp normalize_extra_refs(%{} = refs) do
    if Enum.all?(Map.keys(refs), &is_atom/1) do
      {:ok, refs}
    else
      {:error, :invalid_refs}
    end
  end

  defp normalize_extra_refs(_), do: {:error, :invalid_refs}

  defp normalize_origin_actor(nil, nil), do: {:ok, nil}

  defp normalize_origin_actor(nil, sender_name) when is_binary(sender_name) do
    {:ok, ActorIdentity.programmatic(sender_name)}
  end

  defp normalize_origin_actor(nil, _sender_name), do: {:ok, nil}

  defp normalize_origin_actor(origin_actor, _sender_name) do
    case ActorIdentity.normalize(origin_actor) do
      {:ok, normalized} -> {:ok, normalized}
      {:error, _reason} -> {:error, :invalid_origin_actor}
    end
  end

  defp normalize_request_id(nil), do: {:ok, nil}
  defp normalize_request_id(request_id) when is_binary(request_id), do: {:ok, request_id}
  defp normalize_request_id(_), do: {:error, :invalid_expected_request_id}
end
