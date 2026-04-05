defmodule JidoMurmur.Ingress.Input do
  @moduledoc """
  Canonical ingress input aligned with `jido_ai` control payloads.

  Murmur-specific routing and observability metadata lives inside `refs`.
  """

  alias JidoMurmur.Observability.ConversationCache

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
          | :missing_interaction_id
          | :invalid_interaction_id
          | :missing_workspace_id
          | :invalid_workspace_id
          | :invalid_sender_name
          | :invalid_sender_trace_id
          | :invalid_expected_request_id

  @type session_like :: %{
          required(:id) => String.t(),
          required(:workspace_id) => String.t()
        }

  @spec new(String.t(), keyword()) :: {:ok, t()} | {:error, validation_error()}
  def new(content, opts \\ []) when is_binary(content) and is_list(opts) do
    normalized_content = String.trim(content)

    with :ok <- validate_content(normalized_content),
         {:ok, normalized_source} <- normalize_source(Keyword.get(opts, :source)),
         {:ok, normalized_refs} <- normalize_refs(Keyword.get(opts, :refs, %{})),
         :ok <- validate_required_refs(normalized_refs),
         :ok <- validate_optional_refs(normalized_refs),
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

  @spec from_legacy(session_like(), String.t(), keyword()) :: {:ok, t()} | {:error, validation_error()}
  def from_legacy(session, content, opts \\ []) when is_list(opts) do
    kind = Keyword.get(opts, :kind, :direct)

    interaction_id =
      ConversationCache.resolve(session.id,
        interaction_id: Keyword.get(opts, :interaction_id),
        kind: kind,
        now_ms: Keyword.get(opts, :sent_at_ms, System.monotonic_time(:millisecond))
      )

    legacy_refs =
      %{
        interaction_id: interaction_id,
        kind: kind,
        sender_name: Keyword.get(opts, :sender_name),
        sender_trace_id: Keyword.get(opts, :sender_trace_id),
        workspace_id: session.workspace_id
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    with {:ok, extra_refs} <- normalize_refs(Keyword.get(opts, :refs, %{})) do
      merged_refs = Map.merge(legacy_refs, extra_refs)

      new(content,
        source: Keyword.get(opts, :source, infer_source(kind, Keyword.get(opts, :sender_name))),
        refs: merged_refs,
        expected_request_id: Keyword.get(opts, :expected_request_id)
      )
    end
  end

  @spec control_kind(t()) :: :steer | :inject
  def control_kind(%__MODULE__{source: %{kind: :human}}), do: :steer
  def control_kind(%__MODULE__{source: %{kind: "human"}}), do: :steer
  def control_kind(%__MODULE__{source: :human}), do: :steer
  def control_kind(_input), do: :inject

  @spec validate(t()) :: :ok | {:error, validation_error()}
  def validate(%__MODULE__{} = input) do
    with :ok <- validate_content(input.content),
         {:ok, _source} <- normalize_source(input.source),
         {:ok, refs} <- normalize_refs(input.refs),
         :ok <- validate_required_refs(refs),
         :ok <- validate_optional_refs(refs),
         {:ok, _request_id} <- normalize_request_id(input.expected_request_id) do
      :ok
    end
  end

  @spec interaction_id(t()) :: String.t() | nil
  def interaction_id(%__MODULE__{refs: refs}) do
    Map.get(refs, :interaction_id) || Map.get(refs, "interaction_id")
  end

  defp infer_source(:direct, _sender_name), do: %{kind: :human, via: :workspace_live}

  defp infer_source(kind, sender_name) do
    %{
      kind: :programmatic,
      via: kind,
      sender_name: sender_name
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp validate_content(""), do: {:error, :empty_content}
  defp validate_content(content) when is_binary(content), do: :ok

  defp normalize_source(nil), do: {:error, :missing_source}
  defp normalize_source(%{} = source), do: validate_source_map(source)
  defp normalize_source(:human), do: {:ok, :human}
  defp normalize_source(:programmatic), do: {:ok, :programmatic}
  defp normalize_source(_), do: {:error, :invalid_source}

  defp validate_source_map(source) do
    case ref_value(source, :kind) do
      kind when is_atom(kind) or is_binary(kind) -> {:ok, source}
      _ -> {:error, :invalid_source}
    end
  end

  defp normalize_refs(%{} = refs), do: {:ok, refs}
  defp normalize_refs(_), do: {:error, :invalid_refs}

  defp validate_required_refs(refs) do
    with :ok <- validate_required_ref(refs, :interaction_id, :missing_interaction_id, :invalid_interaction_id),
         :ok <- validate_required_ref(refs, :workspace_id, :missing_workspace_id, :invalid_workspace_id) do
      :ok
    end
  end

  defp validate_required_ref(refs, key, missing_error, invalid_error) do
    case ref_value(refs, key) do
      nil -> {:error, missing_error}
      value when is_binary(value) -> :ok
      _ -> {:error, invalid_error}
    end
  end

  defp validate_optional_refs(refs) do
    with :ok <- validate_optional_ref(refs, :sender_name, :invalid_sender_name),
         :ok <- validate_optional_ref(refs, :sender_trace_id, :invalid_sender_trace_id) do
      :ok
    end
  end

  defp validate_optional_ref(refs, key, error) do
    case ref_value(refs, key) do
      nil -> :ok
      value when is_binary(value) -> :ok
      _ -> {:error, error}
    end
  end

  defp normalize_request_id(nil), do: {:ok, nil}
  defp normalize_request_id(request_id) when is_binary(request_id), do: {:ok, request_id}
  defp normalize_request_id(_), do: {:error, :invalid_expected_request_id}

  defp ref_value(refs, key) when is_atom(key) do
    Map.get(refs, key) || Map.get(refs, Atom.to_string(key))
  end
end
