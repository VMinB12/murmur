defmodule JidoMurmur.Observability.ConversationCache do
  @moduledoc false

  alias JidoMurmur.Observability

  @table :jido_murmur_obs_conversations
  @default_timeout_ms :timer.minutes(1)

  def create_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    else
      @table
    end
  end

  def resolve(session_id, opts \\ []) do
    interaction_id = Keyword.get(opts, :interaction_id)
    kind = Keyword.get(opts, :kind, :direct)
    now_ms = Keyword.get(opts, :now_ms, now_ms())
    timeout_ms = Keyword.get(opts, :timeout_ms, timeout_ms())

    cond do
      kind != :direct ->
        interaction_id || Observability.next_interaction_id()

      is_binary(interaction_id) ->
        put(session_id, interaction_id, now_ms)
        interaction_id

      true ->
        resolve_direct(session_id, now_ms, timeout_ms)
    end
  end

  def put(session_id, interaction_id, now_ms \\ now_ms()) do
    :ets.insert(@table, {session_id, interaction_id, now_ms})
    interaction_id
  end

  def delete(session_id) do
    :ets.delete(@table, session_id)
    :ok
  end

  def lookup(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, interaction_id, last_seen_at_ms}] ->
        %{interaction_id: interaction_id, last_seen_at_ms: last_seen_at_ms}

      [] ->
        nil
    end
  end

  def timeout_ms do
    Application.get_env(:jido_murmur, :conversation_session_timeout_ms, @default_timeout_ms)
  end

  defp resolve_direct(session_id, now_ms, timeout_ms) do
    interaction_id =
      case lookup(session_id) do
        %{interaction_id: cached_id, last_seen_at_ms: last_seen_at_ms}
        when now_ms - last_seen_at_ms <= timeout_ms ->
          cached_id

        _ ->
          Observability.next_interaction_id()
      end

    put(session_id, interaction_id, now_ms)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
