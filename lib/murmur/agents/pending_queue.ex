defmodule Murmur.Agents.PendingQueue do
  @moduledoc """
  ETS-backed message queue for agents that are currently busy.

  When a message (user or inter-agent) arrives for a busy agent, it is
  enqueued here. The Runner drains the queue after each completed request
  and feeds the messages into the next agent loop iteration.
  """

  @table :murmur_pending_messages

  def init do
    :ets.new(@table, [:named_table, :public, :duplicate_bag])
    :ok
  end

  @doc "Enqueue a message for a busy agent session."
  def enqueue(session_id, message) when is_binary(message) do
    :ets.insert(@table, {session_id, message, System.monotonic_time(:nanosecond)})
    :ok
  end

  @doc """
  Atomically drain all pending messages for a session.
  Returns messages in insertion order.
  """
  def drain(session_id) do
    @table
    |> :ets.take(session_id)
    |> Enum.sort_by(&elem(&1, 2))
    |> Enum.map(&elem(&1, 1))
  end

  @doc "Check if there are pending messages for a session."
  def pending?(session_id) do
    :ets.lookup(@table, session_id) != []
  end
end
