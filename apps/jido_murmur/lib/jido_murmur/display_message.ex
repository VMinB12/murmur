defmodule JidoMurmur.DisplayMessage do
  @moduledoc """
  Canonical UI-facing message projection for Murmur chat surfaces.
  """

  alias JidoMurmur.ActorIdentity
  alias JidoMurmur.UITurn.ToolCall

  @enforce_keys [:id, :role, :content]
  defstruct [:id, :request_id, :role, :content, :actor, :sender_name, :thinking, :tool_calls, :usage, :status]

  @type t :: %__MODULE__{
          id: String.t(),
      request_id: String.t() | nil,
          role: String.t(),
          content: String.t(),
          actor: ActorIdentity.t() | nil,
          sender_name: String.t() | nil,
          thinking: String.t() | nil,
          tool_calls: [ToolCall.t()],
          usage: map() | nil,
          status: atom() | nil
        }

  @spec user(String.t(), keyword()) :: t()
  def user(content, opts \\ []) when is_binary(content) do
    actor = normalize_actor(Keyword.get(opts, :actor), ActorIdentity.human())

    %__MODULE__{
      id: Keyword.get(opts, :id, Uniq.UUID.uuid7()),
      request_id: Keyword.get(opts, :request_id),
      role: "user",
      content: content,
      actor: actor,
      sender_name: Keyword.get(opts, :sender_name),
      thinking: Keyword.get(opts, :thinking),
      tool_calls: Keyword.get(opts, :tool_calls, []),
      usage: Keyword.get(opts, :usage),
      status: Keyword.get(opts, :status)
    }
  end

  @spec assistant(String.t(), keyword()) :: t()
  def assistant(content, opts \\ []) when is_binary(content) do
    %__MODULE__{
      id: Keyword.get(opts, :id, Uniq.UUID.uuid7()),
      request_id: Keyword.get(opts, :request_id),
      role: "assistant",
      content: content,
      actor: normalize_actor(Keyword.get(opts, :actor)),
      sender_name: Keyword.get(opts, :sender_name),
      thinking: Keyword.get(opts, :thinking),
      tool_calls: Keyword.get(opts, :tool_calls, []),
      usage: Keyword.get(opts, :usage),
      status: Keyword.get(opts, :status)
    }
  end

  @spec from_received(map()) :: t()
  def from_received(message) when is_map(message) do
    role = to_string(Map.get(message, :role, "user"))
    content = Map.get(message, :content, "")
    sender_name = Map.get(message, :sender_name)
    actor = actor_from_received(message, sender_name)

    case role do
      "assistant" ->
        assistant(content,
          id: Map.get(message, :id, Uniq.UUID.uuid7()),
          request_id: Map.get(message, :request_id),
          actor: actor,
          sender_name: sender_name,
          thinking: Map.get(message, :thinking),
          tool_calls: Map.get(message, :tool_calls, []),
          usage: Map.get(message, :usage),
          status: Map.get(message, :status)
        )

      _ ->
        user(content,
          id: Map.get(message, :id, Uniq.UUID.uuid7()),
          request_id: Map.get(message, :request_id),
          actor: actor,
          sender_name: sender_name,
          thinking: Map.get(message, :thinking),
          tool_calls: Map.get(message, :tool_calls, []),
          usage: Map.get(message, :usage),
          status: Map.get(message, :status)
        )
    end
  end

  @spec label(map()) :: String.t() | nil
  def label(message) when is_map(message) do
    actor = Map.get(message, :actor)
    sender_name = Map.get(message, :sender_name)
    role = Map.get(message, :role)

    cond do
      match?(%ActorIdentity{kind: :human, name: nil}, actor) -> "You"
      match?(%ActorIdentity{kind: :human, name: name} when is_binary(name), actor) -> actor.name
      is_binary(sender_name) -> sender_name
      match?(%ActorIdentity{}, actor) -> ActorIdentity.display_name(actor) || role
      is_binary(role) -> role
      true -> nil
    end
  end

  @spec assistant_message?(map()) :: boolean()
  def assistant_message?(message) when is_map(message), do: Map.get(message, :role) == "assistant"

  @spec human_user_message?(map()) :: boolean()
  def human_user_message?(message) when is_map(message) do
    Map.get(message, :role) == "user" and match?(%ActorIdentity{kind: :human}, Map.get(message, :actor))
  end

  @spec external_user_message?(map()) :: boolean()
  def external_user_message?(message) when is_map(message) do
    Map.get(message, :role) == "user" and not human_user_message?(message)
  end

  @spec with_actor(map(), ActorIdentity.t() | nil, keyword()) :: map()
  def with_actor(message, actor, opts \\ []) when is_map(message) do
    normalized_actor = normalize_actor(actor)

    message
    |> Map.put(:actor, normalized_actor)
    |> maybe_put_sender_name(Keyword.get(opts, :sender_name))
  end

  defp actor_from_received(message, sender_name) do
    message
    |> Map.get(:origin_actor)
    |> normalize_actor(ActorIdentity.from_source(%{kind: :programmatic}, sender_name))
  end

  defp normalize_actor(actor), do: normalize_actor(actor, nil)

  defp normalize_actor(nil, default), do: default

  defp normalize_actor(actor, _default) do
    case ActorIdentity.normalize(actor) do
      {:ok, normalized} -> normalized
      {:error, _reason} -> nil
    end
  end

  defp maybe_put_sender_name(message, nil), do: message
  defp maybe_put_sender_name(message, sender_name), do: Map.put(message, :sender_name, sender_name)

end
