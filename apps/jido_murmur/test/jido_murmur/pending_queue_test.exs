defmodule JidoMurmur.PendingQueueTest do
  use ExUnit.Case, async: false

  alias JidoMurmur.PendingQueue

  setup do
    ensure_ets_table()
    session_id = Ecto.UUID.generate()
    %{session_id: session_id}
  end

  describe "enqueue/2" do
    test "stores a message", %{session_id: session_id} do
      assert :ok = PendingQueue.enqueue(session_id, "hello")
      assert PendingQueue.pending?(session_id)
    end
  end

  describe "drain/1" do
    test "returns and removes all messages in order", %{session_id: session_id} do
      PendingQueue.enqueue(session_id, "first")
      PendingQueue.enqueue(session_id, "second")
      PendingQueue.enqueue(session_id, "third")

      messages = PendingQueue.drain(session_id)
      assert messages == ["first", "second", "third"]
    end

    test "returns empty list when no messages", %{session_id: session_id} do
      assert PendingQueue.drain(session_id) == []
    end

    test "drain clears the queue", %{session_id: session_id} do
      PendingQueue.enqueue(session_id, "msg")
      _ = PendingQueue.drain(session_id)
      refute PendingQueue.pending?(session_id)
    end
  end

  describe "pending?/1" do
    test "returns false when empty", %{session_id: session_id} do
      refute PendingQueue.pending?(session_id)
    end

    test "returns true when messages exist", %{session_id: session_id} do
      PendingQueue.enqueue(session_id, "msg")
      assert PendingQueue.pending?(session_id)
    end
  end

  describe "concurrent access" do
    test "handles concurrent enqueue/drain safely", %{session_id: session_id} do
      # Enqueue from multiple processes concurrently
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            PendingQueue.enqueue(session_id, "msg-#{i}")
          end)
        end

      Enum.each(tasks, &Task.await/1)

      messages = PendingQueue.drain(session_id)
      assert length(messages) == 20
    end
  end

  defp ensure_ets_table do
    unless :ets.whereis(:jido_murmur_pending_messages) != :undefined do
      :ets.new(:jido_murmur_pending_messages, [:named_table, :public, :duplicate_bag])
    end
  rescue
    ArgumentError -> :ok
  end
end
