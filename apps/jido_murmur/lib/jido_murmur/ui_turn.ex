defmodule JidoMurmur.UITurn do
    alias JidoMurmur.ActorIdentity
    alias JidoMurmur.DisplayMessage

  @moduledoc """
  Transforms raw Jido thread entries into structured display groups.

  A UITurn represents one agent "turn" — everything from the LLM receiving a
  prompt until it produces a final answer, including any thinking traces and
  tool call/result pairs along the way.
  """

  defmodule ToolCall do
    @moduledoc false
    defstruct [:id, :name, :args, :result, :status]

    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t(),
            args: map(),
            result: String.t() | nil,
            status: :running | :completed | :error
          }
  end

  defstruct [:id, :thinking, :tool_calls, :content, :sender_name, :status]

  @type t :: %__MODULE__{
          id: String.t(),
          thinking: String.t() | nil,
          tool_calls: [ToolCall.t()],
          content: String.t(),
          sender_name: String.t() | nil,
          status: :thinking | :tool_calling | :completed | :error
        }

  @doc """
  Converts Jido thread entries into display messages that preserve
  thinking and tool call structure.

  Returns a flat list of maps with role/content plus optional
  `:thinking`, `:tool_calls` fields for assistant messages.
  """
  @spec project_entries([struct()]) :: [DisplayMessage.t()]
  def project_entries(entries) when is_list(entries) do
    entries
    |> Enum.map(&normalize_entry/1)
    |> Enum.filter(&relevant_entry?/1)
    |> group_by_request()
    |> Enum.flat_map(&request_group_to_messages/1)
  end

  # --- Private: Entry classification ---

  defp relevant_entry?(%{kind: kind}) when kind in [:message, :ai_message], do: true
  defp relevant_entry?(_), do: false

  defp user_entry?(%{kind: :message}), do: true

  defp user_entry?(%{payload: payload}) do
    role = Map.get(payload, :role)
    to_string(role) == "user"
  end

  defp user_entry?(_), do: false

  # --- Private: Grouping ---

  defp group_by_request(entries) do
    entries
    |> Enum.chunk_while([], &chunk_entry/2, &flush_chunk/1)
    |> Enum.reject(&(&1 == []))
  end

  defp chunk_entry(entry, []) do
    if user_entry?(entry),
      do: {:cont, [entry], []},
      else: {:cont, [entry]}
  end

  defp chunk_entry(entry, acc) do
    cond do
      user_entry?(entry) ->
        {:cont, acc, [entry]}

      user_entry?(hd(acc)) ->
        {:cont, acc, [entry]}

      same_request?(hd(acc), entry) ->
        {:cont, acc ++ [entry]}

      true ->
        {:cont, acc, [entry]}
    end
  end

  defp flush_chunk([]), do: {:cont, []}
  defp flush_chunk(acc), do: {:cont, acc, []}

  defp same_request?(a, b) do
    req_a = get_request_id(a)
    req_a != nil and req_a == get_request_id(b)
  end

  defp get_request_id(%{payload: payload}) do
    Map.get(payload, :request_id)
  end

  # --- Private: Group → Messages ---

  defp request_group_to_messages(entries) do
    first = hd(entries)

    if user_entry?(first) do
      build_user_message(first)
    else
      build_assistant_turn(entries)
    end
  end

  defp build_user_message(entry) do
    payload = Map.get(entry, :payload, %{})
    refs = Map.get(entry, :refs, %{})
    content = Map.get(payload, :content, "")
    request_id = Map.get(payload, :request_id)
    payload_sender_name = Map.get(payload, :sender_name)
    actor = normalize_actor(Map.get(payload, :origin_actor) || Map.get(refs, :origin_actor), default_user_actor(entry, payload_sender_name))
    sender_name = payload_sender_name || actor_display_name(actor)

    [
      DisplayMessage.user(content,
        id: Map.get(entry, :id, Uniq.UUID.uuid7()),
        request_id: request_id,
        actor: actor,
        sender_name: sender_name
      )
    ]
  end

  defp build_assistant_turn(entries) do
    request_id = get_request_id(hd(entries))
    {thinking, tool_calls, content, sender_name, actor} =
      Enum.reduce(entries, {nil, [], "", nil, nil}, &reduce_entry/2)

    id =
      if is_binary(request_id) do
        request_id <> "-turn"
      else
        (hd(entries).id || Uniq.UUID.uuid7()) <> "-turn"
      end

    [
      DisplayMessage.assistant(content,
        id: id,
        request_id: request_id,
        actor: actor,
        sender_name: sender_name,
        thinking: if(thinking && thinking != "", do: thinking),
        tool_calls: tool_calls
      )
    ]
  end

  defp reduce_entry(entry, acc) do
    payload = Map.get(entry, :payload, %{})
    refs = Map.get(entry, :refs, %{})
    role = to_string(Map.get(payload, :role))

    case role do
      "assistant" -> reduce_assistant(payload, refs, acc)
      "tool" -> reduce_tool(payload, acc)
      _ -> acc
    end
  end

  defp reduce_assistant(payload, refs, {think, tools, _text, _name, actor}) do
    new_think = Map.get(payload, :thinking) || think
    new_text = Map.get(payload, :content, "")
    payload_sender_name = Map.get(payload, :sender_name)
    raw_tcs = Map.get(payload, :tool_calls, [])
    new_actor = normalize_actor(Map.get(payload, :current_actor) || Map.get(refs, :current_actor), actor_from_sender_name(payload_sender_name, actor))
    new_name = payload_sender_name || actor_display_name(new_actor)

    new_tools = tools ++ Enum.map(raw_tcs, &parse_tool_call/1)

    {new_think, new_tools, new_text, new_name, new_actor}
  end

  defp reduce_tool(payload, {think, tools, text, name, actor}) do
    call_id = Map.get(payload, :tool_call_id)
    result_content = Map.get(payload, :content, "")

    updated_tools =
      Enum.map(tools, fn tc ->
        if tc.id == call_id, do: %{tc | result: result_content, status: :completed}, else: tc
      end)

    {think, updated_tools, text, name, actor}
  end

  defp parse_tool_call(tc) do
    %ToolCall{
      id: tc_field(tc, :id),
      name: tc_field(tc, :name) || tc_field(tc, :function_name),
      args: tc_field(tc, :arguments) || tc_field(tc, :args) || %{},
      result: nil,
      status: :running
    }
  end

  defp normalize_actor(nil, default), do: default

  defp normalize_actor(actor, _default) do
    case ActorIdentity.normalize(actor) do
      {:ok, normalized} -> normalized
      {:error, _reason} -> nil
    end
  end

  defp default_user_actor(%{kind: :message}, sender_name), do: ActorIdentity.human(sender_name)
  defp default_user_actor(_entry, sender_name) when is_binary(sender_name), do: ActorIdentity.unknown(sender_name)
  defp default_user_actor(_entry, _sender_name), do: ActorIdentity.human()

  defp actor_from_sender_name(nil, actor), do: actor
  defp actor_from_sender_name(sender_name, _actor), do: ActorIdentity.unknown(sender_name)

  defp actor_display_name(nil), do: nil
  defp actor_display_name(%ActorIdentity{kind: :human, name: nil}), do: "You"
  defp actor_display_name(actor), do: ActorIdentity.display_name(actor)

  defp tc_field(tc, key) when is_struct(tc), do: Map.get(tc, key)
  defp tc_field(tc, key) when is_map(tc), do: Map.get(tc, key)

  defp normalize_entry(entry) do
    %{
      id: Map.get(entry, :id) || Map.get(entry, "id"),
      kind: Map.get(entry, :kind) || Map.get(entry, "kind"),
      payload: normalize_map(Map.get(entry, :payload) || Map.get(entry, "payload") || %{}),
      refs: normalize_map(Map.get(entry, :refs) || Map.get(entry, "refs") || %{})
    }
  end

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
  defp normalize_key("status"), do: :status
  defp normalize_key("thinking"), do: :thinking
  defp normalize_key("tool_call_id"), do: :tool_call_id
  defp normalize_key("tool_calls"), do: :tool_calls
  defp normalize_key(key), do: key
end
