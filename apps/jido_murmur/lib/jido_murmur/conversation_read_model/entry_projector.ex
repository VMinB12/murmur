defmodule JidoMurmur.ConversationReadModel.EntryProjector do
  @moduledoc false

  alias JidoMurmur.ActorIdentity
  alias JidoMurmur.ConversationReadModel.Turn
  alias JidoMurmur.DisplayMessage
  alias JidoMurmur.DisplayMessage.ToolCall

  @spec project_entries([struct() | map()]) :: [DisplayMessage.t()]
  def project_entries(entries) when is_list(entries) do
    entries
    |> Enum.map(&normalize_entry/1)
    |> Enum.filter(&relevant_entry?/1)
    |> Enum.reduce({[], %{}}, &reduce_entry/2)
    |> elem(0)
    |> DisplayMessage.sort_messages()
  end

  defp reduce_entry(entry, {messages, step_indexes}) do
    cond do
      user_entry?(entry) ->
        {messages ++ [build_user_message(entry)], step_indexes}

      assistant_entry?(entry) ->
        request_id = get_request_id(entry)
        step_index = next_step_index(step_indexes, request_id)
        message = build_assistant_step(entry, request_id, step_index)

        {messages ++ [message], put_step_index(step_indexes, request_id, step_index)}

      tool_entry?(entry) ->
        {merge_tool_result(messages, entry), step_indexes}

      true ->
        {messages, step_indexes}
    end
  end

  defp merge_tool_result(messages, entry) do
    request_id = get_request_id(entry)

    case latest_assistant_step(messages, request_id) do
      {message, index} ->
        updated =
          Turn.put_persisted_tool_result(
            message,
            Map.get(entry.payload, :tool_call_id),
            Map.get(entry.payload, :content, "")
          )

        List.replace_at(messages, index, updated)

      nil ->
        messages
    end
  end

  defp build_user_message(entry) do
    payload = entry.payload
    refs = entry.refs
    content = Map.get(payload, :content, "")
    request_id = get_request_id(entry)
    payload_sender_name = Map.get(payload, :sender_name)

    actor =
      normalize_actor(
        Map.get(payload, :origin_actor) || Map.get(refs, :origin_actor),
        default_user_actor(entry, payload_sender_name)
      )

    sender_name = payload_sender_name || actor_display_name(actor)

    DisplayMessage.user(content,
      id: Map.get(entry, :id, Uniq.UUID.uuid7()),
      request_id: request_id,
      actor: actor,
      sender_name: sender_name,
      first_seen_at: Map.get(entry, :at),
      first_seen_seq: Map.get(entry, :seq)
    )
  end

  defp build_assistant_step(entry, request_id, step_index) do
    payload = entry.payload
    refs = entry.refs
    payload_sender_name = Map.get(payload, :sender_name)

    actor =
      normalize_actor(
        Map.get(payload, :current_actor) || Map.get(refs, :current_actor),
        actor_from_sender_name(payload_sender_name, nil)
      )

    sender_name = payload_sender_name || actor_display_name(actor)
    tool_calls = Enum.map(Map.get(payload, :tool_calls, []), &parse_tool_call/1)

    DisplayMessage.assistant(Map.get(payload, :content, ""),
      id: assistant_step_id(entry, request_id, step_index),
      request_id: request_id,
      step_index: step_index,
      actor: actor,
      sender_name: sender_name,
      thinking: blank_to_nil(Map.get(payload, :thinking)),
      tool_calls: tool_calls,
      status: if(tool_calls == [], do: :completed, else: :running),
      first_seen_at: Map.get(entry, :at),
      first_seen_seq: Map.get(entry, :seq)
    )
  end

  defp assistant_step_id(_entry, request_id, step_index) when is_binary(request_id) do
    Turn.step_id(request_id, step_index)
  end

  defp assistant_step_id(entry, _request_id, _step_index) do
    (Map.get(entry, :id) || Uniq.UUID.uuid7()) <> "-step"
  end

  defp next_step_index(step_indexes, request_id) when is_binary(request_id) do
    Map.get(step_indexes, request_id, 0) + 1
  end

  defp next_step_index(_step_indexes, _request_id), do: 1

  defp put_step_index(step_indexes, request_id, step_index) when is_binary(request_id) do
    Map.put(step_indexes, request_id, step_index)
  end

  defp put_step_index(step_indexes, _request_id, _step_index), do: step_indexes

  defp latest_assistant_step(messages, request_id) do
    messages
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(fn {message, index} ->
      if DisplayMessage.assistant_message?(message) and Map.get(message, :request_id) == request_id do
        {message, index}
      end
    end)
  end

  defp parse_tool_call(tool_call) do
    %ToolCall{
      id: tc_field(tool_call, :id),
      name: tc_field(tool_call, :name) || tc_field(tool_call, :function_name),
      args: tc_field(tool_call, :arguments) || tc_field(tool_call, :args) || %{},
      result: nil,
      status: :running
    }
  end

  defp relevant_entry?(%{kind: kind}) when kind in [:message, :ai_message], do: true
  defp relevant_entry?(_entry), do: false

  defp user_entry?(%{kind: :message}), do: true

  defp user_entry?(%{payload: payload}) do
    to_string(Map.get(payload, :role)) == "user"
  end

  defp user_entry?(_entry), do: false

  defp assistant_entry?(%{payload: payload}) do
    to_string(Map.get(payload, :role)) == "assistant"
  end

  defp assistant_entry?(_entry), do: false

  defp tool_entry?(%{payload: payload}) do
    to_string(Map.get(payload, :role)) == "tool"
  end

  defp tool_entry?(_entry), do: false

  defp get_request_id(%{payload: payload, refs: refs}) do
    Map.get(payload, :request_id) || Map.get(refs, :request_id)
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

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp tc_field(tool_call, key) when is_struct(tool_call), do: Map.get(tool_call, key)
  defp tc_field(tool_call, key) when is_map(tool_call), do: Map.get(tool_call, key)

  defp normalize_entry(entry) do
    %{
      id: Map.get(entry, :id) || Map.get(entry, "id"),
      seq: Map.get(entry, :seq) || Map.get(entry, "seq"),
      at: Map.get(entry, :at) || Map.get(entry, "at"),
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
  defp normalize_key("seq"), do: :seq
  defp normalize_key("status"), do: :status
  defp normalize_key("thinking"), do: :thinking
  defp normalize_key("tool_call_id"), do: :tool_call_id
  defp normalize_key("tool_calls"), do: :tool_calls
  defp normalize_key(key), do: key
end
