defmodule JidoMurmur.ConversationReadModel.EntryProjector do
  @moduledoc false

  alias Jido.Signal.ID, as: SignalID
  alias JidoMurmur.ActorIdentity
  alias JidoMurmur.ConversationReadModel
  alias JidoMurmur.ConversationReadModel.ReplayEntry
  alias JidoMurmur.ConversationReadModel.Turn
  alias JidoMurmur.DisplayMessage
  alias JidoMurmur.DisplayMessage.ToolCall

  @spec project_entries(String.t(), [struct() | map()]) :: ConversationReadModel.t()
  def project_entries(session_id, entries) when is_binary(session_id) and is_list(entries) do
    entries
    |> Enum.map(&ReplayEntry.normalize/1)
    |> Enum.filter(&ReplayEntry.relevant?/1)
    |> Enum.reduce(ConversationReadModel.new(session_id), &reduce_entry/2)
  end

  defp reduce_entry(entry, model) do
    cond do
      ReplayEntry.user?(entry) ->
        ConversationReadModel.put_message(model, build_user_message(entry))

      ReplayEntry.assistant?(entry) ->
        request_id = ReplayEntry.request_id(entry)
        step_index = ConversationReadModel.next_step_index(model, request_id)
        message = build_assistant_step(entry, request_id, step_index)

        ConversationReadModel.put_message(model, message)

      ReplayEntry.tool?(entry) ->
        ConversationReadModel.attach_persisted_tool_result(
          model,
          ReplayEntry.request_id(entry),
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
    request_id = ReplayEntry.request_id(entry)
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
    tool_calls = Enum.map(Map.get(payload, :tool_calls, []), &tool_call/1)

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

  defp tool_call(tool_call) do
    %ToolCall{
      id: Map.get(tool_call, :id),
      name: Map.get(tool_call, :name),
      args: Map.get(tool_call, :args, %{}),
      result: nil,
      status: :running
    }
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
end
