defmodule JidoMurmur.PendingQueue do
  @moduledoc """
  ETS-backed message queue for agents that are currently busy.
  """
  @table :jido_murmur_pending_messages

  def enqueue(session_id, message) when is_binary(message) do
    :ets.insert(@table, {session_id, message, System.monotonic_time(:nanosecond)})
    :ok
  end

  def drain(session_id) do
    @table
    |> :ets.take(session_id)
    |> Enum.sort_by(&elem(&1, 2))
    |> Enum.map(&elem(&1, 1))
  end

  def pending?(session_id) do
    :ets.lookup(@table, session_id) != []
  end
end
