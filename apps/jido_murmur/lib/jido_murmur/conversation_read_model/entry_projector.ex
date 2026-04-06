defmodule JidoMurmur.ConversationReadModel.EntryProjector do
  @moduledoc false

  alias Jido.Signal.ID, as: SignalID
  alias JidoMurmur.ActorIdentity
  alias JidoMurmur.ConversationReadModel
  alias JidoMurmur.ConversationReadModel.Turn
  alias JidoMurmur.DisplayMessage
  alias JidoMurmur.DisplayMessage.ToolCall

  @spec project_entries(String.t(), [struct() | map()]) :: ConversationReadModel.t()
  def project_entries(session_id, entries) when is_binary(session_id) and is_list(entries) do
    entries
    |> Enum.map(&normalize_entry/1)
    |> Enum.filter(&relevant_entry?/1)
    |> Enum.reduce(ConversationReadModel.new(session_id), &reduce_entry/2)
  end

  defp reduce_entry(entry, model) do
    cond do
      user_entry?(entry) ->
        ConversationReadModel.put_message(model, build_user_message(entry))

      assistant_entry?(entry) ->
        request_id = get_request_id(entry)
        step_index = ConversationReadModel.next_step_index(model, request_id)
        message = build_assistant_step(entry, request_id, step_index)

        ConversationReadModel.put_message(model, message)

      tool_entry?(entry) ->
        ConversationReadModel.attach_persisted_tool_result(
          model,
          get_request_id(entry),
          Map.get(entry.payload, :tool_call_id),
          Map.get(entry.payload, :content, "")
        )

      true ->
        model
    end
  end

  defp build_user_message(entry) do
    payload = entry.payload
    refs = entry.refs
    content = Map.get(payload, :content, "")
    request_id = get_request_id(entry)
    payload_sender_name = Map.get(payload, :sender_name)
    message_id = user_message_id(entry)

    actor =
      normalize_actor(
        Map.get(payload, :origin_actor) || Map.get(refs, :origin_actor),
        default_user_actor(entry, payload_sender_name)
      )

    sender_name = payload_sender_name || actor_display_name(actor)

    DisplayMessage.user(content,
      id: message_id,
      request_id: request_id,
      actor: actor,
      sender_name: sender_name,
      first_seen_at: user_first_seen_at(entry, message_id),
      first_seen_seq: user_first_seen_seq(entry, message_id)
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

  defp user_message_id(entry) do
    Map.get(entry.refs, :message_id) || Map.get(entry, :id) || Uniq.UUID.uuid7()
  end

  defp user_first_seen_at(entry, message_id) do
    Map.get(entry.refs, :message_first_seen_at) ||
      if(is_binary(message_id) and SignalID.valid?(message_id),
        do: SignalID.extract_timestamp(message_id),
        else: Map.get(entry, :at)
      )
  end

  defp user_first_seen_seq(entry, message_id) do
    Map.get(entry.refs, :message_first_seen_seq) ||
      if(is_binary(message_id) and SignalID.valid?(message_id),
        do: SignalID.sequence_number(message_id),
        else: Map.get(entry, :seq)
      )
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
