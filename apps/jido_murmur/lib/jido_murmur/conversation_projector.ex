defmodule JidoMurmur.ConversationProjector do
  @moduledoc """
  Core-owned projector for canonical conversation snapshots and UI-facing
  updates.
  """

  alias JidoMurmur.Catalog
  alias JidoMurmur.ConversationReadModel
  alias JidoMurmur.DisplayMessage
  alias JidoMurmur.Signals.ConversationUpdated

  @table :jido_murmur_conversation_snapshots

  @type session_like :: %{
          required(:id) => String.t(),
          required(:workspace_id) => String.t(),
          required(:agent_profile_id) => String.t(),
          optional(atom()) => any()
        }

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

    next_model = upsert_message(model, display_message)
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
    entries = extract_entries(session)

    {candidate_model, candidate_latest_message} = ConversationReadModel.reconcile_entries(previous_model, entries)

    {next_model, latest_message} =
      case choose_snapshot_model(previous_model, candidate_model) do
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
        session_id
        |> ConversationReadModel.from_entries(extract_entries_from_agent(agent))
        |> tap(fn model -> put_snapshot(session_id, model) end)

      model ->
        model
    end
  end

  defp load_model(session) do
    ConversationReadModel.from_entries(session.id, extract_entries(session))
  end

  defp extract_entries(session) do
    jido_mod = JidoMurmur.jido_mod()

    case safe_whereis(jido_mod, session.id) do
      pid when is_pid(pid) ->
        case Jido.AgentServer.state(pid) do
          {:ok, %{agent: agent}} -> extract_entries_from_agent(agent)
          _ -> extract_entries_from_storage(session)
        end

      _ ->
        extract_entries_from_storage(session)
    end
  end

  defp safe_whereis(jido_mod, session_id) do
    jido_mod.whereis(session_id)
  rescue
    ArgumentError -> nil
  end

  defp extract_entries_from_storage(session) do
    agent_module = Catalog.agent_module(session.agent_profile_id)

    case JidoMurmur.jido_mod().thaw(agent_module, session.id) do
      {:ok, agent} -> extract_entries_from_agent(agent)
      {:error, :not_found} -> []
    end
  end

  defp extract_entries_from_agent(%{state: %{__thread__: %{entries: entries}}}) when is_list(entries), do: entries
  defp extract_entries_from_agent(_agent), do: []

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
    fresh_model =
      case load_model(session) do
        %ConversationReadModel{messages: []} ->
          ConversationReadModel.from_entries(session.id, extract_entries_from_storage(session))

        %ConversationReadModel{} = model ->
          model
      end

    resolved_model = choose_snapshot_model(cached_model, fresh_model)

    if resolved_model != cached_model do
      put_snapshot(session.id, resolved_model)
    end

    resolved_model.messages
  end

  defp choose_snapshot_model(%ConversationReadModel{} = cached_model, %ConversationReadModel{messages: []}) do
    cached_model
  end

  defp choose_snapshot_model(%ConversationReadModel{messages: []}, %ConversationReadModel{} = fresh_model) do
    fresh_model
  end

  defp choose_snapshot_model(%ConversationReadModel{} = cached_model, %ConversationReadModel{} = fresh_model) do
    case compare_model_freshness(fresh_model, cached_model) do
      :gt -> fresh_model
      _ -> cached_model
    end
  end

  defp compare_model_freshness(%ConversationReadModel{} = left, %ConversationReadModel{} = right) do
    freshness_signature(left)
    |> compare_signatures(freshness_signature(right))
  end

  defp compare_signatures(left, right) when left > right, do: :gt
  defp compare_signatures(left, right) when left < right, do: :lt
  defp compare_signatures(_left, _right), do: :eq

  defp freshness_signature(%ConversationReadModel{messages: messages}) do
    {latest_message_marker(messages), length(messages), total_message_weight(messages)}
  end

  defp latest_message_marker(messages) do
    messages
    |> Enum.map(&message_marker/1)
    |> Enum.max(fn -> {0, 0} end)
  end

  defp message_marker(message) do
    {Map.get(message, :first_seen_at) || 0, Map.get(message, :first_seen_seq) || 0}
  end

  defp total_message_weight(messages) do
    Enum.reduce(messages, 0, fn message, total -> total + message_weight(message) end)
  end

  defp message_weight(message) do
    content_weight = message |> Map.get(:content, "") |> to_string() |> String.length()
    thinking_weight = message |> Map.get(:thinking, "") |> to_string() |> String.length()

    tool_weight =
      message
      |> Map.get(:tool_calls, [])
      |> Enum.reduce(0, fn tool_call, total ->
        result_length = tool_call |> Map.get(:result, "") |> to_string() |> String.length()
        args_size = tool_call |> Map.get(:args, %{}) |> map_size()
        total + result_length + args_size
      end)

    usage_weight =
      message
      |> Map.get(:usage)
      |> case do
        usage when is_map(usage) -> map_size(usage)
        _ -> 0
      end

    content_weight + thinking_weight + tool_weight + usage_weight
  end

  defp upsert_message(%ConversationReadModel{} = model, %DisplayMessage{} = message) do
    case Enum.find_index(model.messages, &(&1.id == message.id)) do
      nil -> ConversationReadModel.put_message(model, message)
      index -> ConversationReadModel.replace_message(model, index, message)
    end
  end
end
