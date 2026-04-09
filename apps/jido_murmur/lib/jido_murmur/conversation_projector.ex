defmodule JidoMurmur.ConversationProjector do
  @moduledoc """
  Core-owned projector for canonical conversation snapshots and UI-facing
  updates.
  """

  alias JidoMurmur.ConversationReadModel
  alias JidoMurmur.ConversationSnapshotSource
  alias JidoMurmur.DisplayMessage
  alias JidoMurmur.SessionContract
  alias JidoMurmur.Signals.ConversationUpdated

  @table :jido_murmur_conversation_snapshots

  @type session_like :: SessionContract.identity()

  @spec snapshot(session_like()) :: [DisplayMessage.t()]
  def snapshot(session) do
    case get_snapshot(session.id) do
      nil -> load_snapshot(session)
      %ConversationReadModel{} = model -> refresh_snapshot(session, model)
    end
  end

  @spec load_snapshot(session_like()) :: [DisplayMessage.t()]
  def load_snapshot(session) do
    model = load_model(session)
    put_snapshot(session.id, model)
    model.messages
  end

  @spec put_received_message(session_like(), map()) :: DisplayMessage.t()
  def put_received_message(session, message) when is_map(session) and is_binary(session.id) and is_map(message) do
    display_message = DisplayMessage.from_received(message)

    model =
      case get_snapshot(session.id) do
        nil -> load_model(session)
        %ConversationReadModel{} = snapshot -> snapshot
      end

    next_model =
      model
      |> upsert_message(display_message)
      |> ConversationReadModel.advance_live_revision(:visible_message)

    put_snapshot(session.id, next_model)
    display_message
  end

  @spec clear(String.t()) :: true
  def clear(session_id) when is_binary(session_id) do
    :ets.delete(@table, session_id)
  end

  @spec apply_signal(String.t(), String.t(), map(), Jido.Signal.t()) :: {:ok, DisplayMessage.t()} | :ignore
  def apply_signal(workspace_id, session_id, agent, %Jido.Signal{} = signal)
      when is_binary(workspace_id) and is_binary(session_id) and is_map(agent) do
    model = ensure_model(session_id, agent)

    case ConversationReadModel.apply_signal(model, signal) do
      {:ok, next_model, message} ->
        put_snapshot(session_id, next_model)
        broadcast_update(workspace_id, session_id, message)
        {:ok, message}

      :ignore ->
        :ignore
    end
  end

  @spec reconcile_session(session_like()) :: [DisplayMessage.t()]
  def reconcile_session(session) do
    previous_model = get_snapshot(session.id) || ConversationReadModel.new(session.id)
    source = ConversationSnapshotSource.load(session)

    {candidate_model, candidate_latest_message} =
      ConversationReadModel.reconcile_entries(previous_model, source.entries,
        source: source.source,
        persisted_rev: source.persisted_rev
      )

    {next_model, latest_message} =
      case choose_snapshot_model(:reconcile, previous_model, candidate_model) do
        ^previous_model -> {previous_model, nil}
        %ConversationReadModel{} = resolved_model -> {resolved_model, candidate_latest_message}
      end

    put_snapshot(session.id, next_model)

    case latest_message do
      nil -> :ok
      message -> broadcast_update(session.workspace_id, session.id, message)
    end

    next_model.messages
  end

  @spec latest_assistant_message(String.t()) :: DisplayMessage.t() | nil
  def latest_assistant_message(session_id) when is_binary(session_id) do
    session_id
    |> get_snapshot()
    |> case do
      %ConversationReadModel{messages: messages} ->
        messages
        |> Enum.reverse()
        |> Enum.find(&DisplayMessage.assistant_message?/1)

      _ ->
        nil
    end
  end

  defp ensure_model(session_id, agent) do
    case get_snapshot(session_id) do
      nil ->
        model =
          case ConversationSnapshotSource.from_agent(agent) do
            %ConversationSnapshotSource{} = source -> build_model(session_id, source)
            nil -> ConversationReadModel.new(session_id)
          end

        put_snapshot(session_id, model)
        model

      model ->
        model
    end
  end

  defp load_model(session) do
    session
    |> ConversationSnapshotSource.load()
    |> then(&build_model(session.id, &1))
  end

  defp broadcast_update(workspace_id, session_id, %DisplayMessage{} = message) do
    signal =
      ConversationUpdated.new!(
        %{session_id: session_id, message: message},
        subject: ConversationUpdated.subject(workspace_id, session_id)
      )

    Phoenix.PubSub.broadcast(JidoMurmur.pubsub(), JidoMurmur.Topics.agent_conversation(workspace_id, session_id), signal)
  end

  defp get_snapshot(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, %ConversationReadModel{} = model}] -> model
      _ -> nil
    end
  end

  defp put_snapshot(session_id, %ConversationReadModel{} = model) do
    :ets.insert(@table, {session_id, model})
  end

  defp refresh_snapshot(session, %ConversationReadModel{} = cached_model) do
    fresh_model = load_model(session)

    resolved_model = choose_snapshot_model(:refresh, cached_model, fresh_model)

    if resolved_model != cached_model do
      put_snapshot(session.id, resolved_model)
    end

    resolved_model.messages
  end

  defp build_model(session_id, %ConversationSnapshotSource{} = source) do
    ConversationReadModel.from_entries(session_id, source.entries,
      source: source.source,
      persisted_rev: source.persisted_rev
    )
  end

  defp choose_snapshot_model(
         :refresh,
         %ConversationReadModel{} = cached_model,
         %ConversationReadModel{source: :live_thread} = fresh_model
       ) do
    if ConversationReadModel.ahead_of_persistence?(cached_model) do
      cached_model
    else
      choose_snapshot_model(:reconcile, cached_model, fresh_model)
    end
  end

  defp choose_snapshot_model(
         _mode,
         %ConversationReadModel{messages: [_ | _]} = cached_model,
         %ConversationReadModel{messages: []}
       ) do
    cached_model
  end

  defp choose_snapshot_model(:refresh, %ConversationReadModel{} = cached_model, %ConversationReadModel{} = fresh_model) do
    choose_snapshot_model(:reconcile, cached_model, fresh_model)
  end

  defp choose_snapshot_model(:reconcile, %ConversationReadModel{} = cached_model, %ConversationReadModel{} = fresh_model) do
    if replay_confirms_cache?(cached_model, fresh_model) do
      fresh_model
    else
      cached_model
    end
  end

  defp replay_confirms_cache?(%ConversationReadModel{} = cached_model, %ConversationReadModel{} = fresh_model) do
    fresh_model.persisted_rev > cached_model.persisted_rev and
      replay_supersedes_cache?(cached_model, fresh_model)
  end

  defp replay_supersedes_cache?(%ConversationReadModel{} = cached_model, %ConversationReadModel{} = fresh_model) do
    if ConversationReadModel.ahead_of_persistence?(cached_model) do
      cached_ids_confirmed?(cached_model.messages, fresh_model.messages)
    else
      true
    end
  end

  defp cached_ids_confirmed?([], _fresh_messages), do: true

  defp cached_ids_confirmed?(cached_messages, fresh_messages) do
    cached_ids = MapSet.new(Enum.map(cached_messages, & &1.id))
    fresh_ids = MapSet.new(Enum.map(fresh_messages, & &1.id))

    MapSet.subset?(cached_ids, fresh_ids)
  end

  defp upsert_message(%ConversationReadModel{} = model, %DisplayMessage{} = message) do
    case Enum.find_index(model.messages, &(&1.id == message.id)) do
      nil -> ConversationReadModel.put_message(model, message)
      index -> ConversationReadModel.replace_message(model, index, message)
    end
  end
end
