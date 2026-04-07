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
          required(:agent_profile_id) => String.t()
        }

  @spec snapshot(session_like()) :: [DisplayMessage.t()]
  def snapshot(session) do
    case get_snapshot(session.id) do
      nil -> load_snapshot(session)
      model -> model.messages
    end
  end

  @spec load_snapshot(session_like()) :: [DisplayMessage.t()]
  def load_snapshot(session) do
    model = load_model(session)
    put_snapshot(session.id, model)
    model.messages
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
    {next_model, latest_message} = ConversationReadModel.reconcile_entries(previous_model, extract_entries(session))
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
end
