defmodule JidoMurmur.PendingQueue do
  @moduledoc """
  ETS-backed message queue for agents that are currently busy.
  """

  alias JidoMurmur.Observability

  @table :jido_murmur_pending_messages

  def enqueue(session_id, message) when is_binary(message) do
    enqueue(session_id, Observability.build_message_envelope(message))
  end

  def enqueue(session_id, %{} = envelope) do
    :ets.insert(@table, {session_id, normalize_envelope(envelope), System.monotonic_time(:nanosecond)})
    :ok
  end

  def drain(session_id) do
    session_id
    |> drain_envelopes()
    |> Enum.map(& &1.content)
  end

  def drain_envelopes(session_id) do
    @table
    |> :ets.take(session_id)
    |> Enum.sort_by(&elem(&1, 2))
    |> Enum.map(&elem(&1, 1))
  end

  def pending?(session_id) do
    :ets.lookup(@table, session_id) != []
  end

  defp normalize_envelope(%{content: content} = envelope) when is_binary(content) do
    envelope
    |> Map.put_new(:id, Uniq.UUID.uuid7())
    |> Map.put_new(:role, "user")
    |> Map.put_new(:kind, :direct)
    |> Map.put_new(:interaction_id, Observability.next_interaction_id())
  end
end
