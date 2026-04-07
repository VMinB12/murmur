defmodule JidoMurmur.ConversationReadModel.ReplayEntry do
  @moduledoc false

  alias JidoMurmur.ActorIdentity

  @enforce_keys [:payload, :refs]
  defstruct [:id, :seq, :at, :kind, payload: %{}, refs: %{}]

  @type tool_call :: %{
          optional(:id) => String.t(),
          optional(:name) => String.t(),
          optional(:args) => map()
        }

  @type t :: %__MODULE__{
          id: String.t() | nil,
          seq: non_neg_integer() | nil,
          at: integer() | nil,
          kind: atom() | String.t() | nil,
          payload: map(),
          refs: map()
        }

  @spec normalize(struct() | map()) :: t()
  def normalize(entry) do
    %__MODULE__{
      id: entry_field(entry, :id),
      seq: entry_field(entry, :seq),
      at: entry_field(entry, :at),
      kind: normalize_kind(entry_field(entry, :kind)),
      payload: normalize_payload(entry_field(entry, :payload) || %{}),
      refs: normalize_map(entry_field(entry, :refs) || %{})
    }
  end

  @spec relevant?(t()) :: boolean()
  def relevant?(%__MODULE__{kind: kind}) when kind in [:message, :ai_message], do: true
  def relevant?(_entry), do: false

  @spec user?(t()) :: boolean()
  def user?(%__MODULE__{kind: :message}), do: true
  def user?(%__MODULE__{payload: %{role: "user"}}), do: true
  def user?(_entry), do: false

  @spec assistant?(t()) :: boolean()
  def assistant?(%__MODULE__{payload: %{role: "assistant"}}), do: true
  def assistant?(_entry), do: false

  @spec tool?(t()) :: boolean()
  def tool?(%__MODULE__{payload: %{role: "tool"}}), do: true
  def tool?(_entry), do: false

  @spec request_id(t()) :: String.t() | nil
  def request_id(%__MODULE__{payload: payload, refs: refs}) do
    Map.get(payload, :request_id) || Map.get(refs, :request_id)
  end

  defp entry_field(entry, key) when is_map(entry) do
    Map.get(entry, key) || Map.get(entry, Atom.to_string(key))
  end

  defp normalize_kind("message"), do: :message
  defp normalize_kind("ai_message"), do: :ai_message
  defp normalize_kind(kind), do: kind

  defp normalize_payload(%{} = payload) do
    payload
    |> normalize_map()
    |> normalize_payload_tool_calls()
  end

  defp normalize_payload(other), do: other

  defp normalize_payload_tool_calls(%{} = payload) do
    case Map.get(payload, :tool_calls) do
      tool_calls when is_list(tool_calls) -> Map.put(payload, :tool_calls, Enum.map(tool_calls, &normalize_tool_call/1))
      _ -> payload
    end
  end

  defp normalize_tool_call(tool_call) when is_map(tool_call) do
    normalized = normalize_map(tool_call)

    %{
      id: Map.get(normalized, :id),
      name: Map.get(normalized, :name) || Map.get(normalized, :function_name),
      args: Map.get(normalized, :args) || Map.get(normalized, :arguments) || %{}
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_tool_call(other), do: other

  defp normalize_map(value) when is_list(value), do: Enum.map(value, &normalize_map/1)
  defp normalize_map(%ActorIdentity{} = value), do: value

  defp normalize_map(value) when is_map(value) do
    Map.new(value, fn {key, map_value} ->
      {normalize_key(key), normalize_map(map_value)}
    end)
  end

  defp normalize_map(value), do: value

  defp normalize_key("args"), do: :args
  defp normalize_key("arguments"), do: :arguments
  defp normalize_key("content"), do: :content
  defp normalize_key("current_actor"), do: :current_actor
  defp normalize_key("function_name"), do: :function_name
  defp normalize_key("id"), do: :id
  defp normalize_key("kind"), do: :kind
  defp normalize_key("name"), do: :name
  defp normalize_key("origin_actor"), do: :origin_actor
  defp normalize_key("request_id"), do: :request_id
  defp normalize_key("role"), do: :role
  defp normalize_key("sender_name"), do: :sender_name
  defp normalize_key("seq"), do: :seq
  defp normalize_key("status"), do: :status
  defp normalize_key("thinking"), do: :thinking
  defp normalize_key("tool_call_id"), do: :tool_call_id
  defp normalize_key("tool_calls"), do: :tool_calls
  defp normalize_key(key), do: key
end
