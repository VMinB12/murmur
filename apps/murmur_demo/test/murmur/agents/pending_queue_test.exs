defmodule Murmur.Agents.PendingQueueTest do
  use ExUnit.Case, async: true

  alias JidoMurmur.PendingQueue

  setup do
    # Use the real table since init is called at app startup.
    # But we ensure isolation by using unique session IDs per test.
    session_id = Ecto.UUID.generate()
    {:ok, session_id: session_id}
  end

  describe "enqueue/2 and drain/1" do
    test "drain returns empty list when no messages queued", %{session_id: session_id} do
      assert PendingQueue.drain(session_id) == []
    end

    test "enqueue stores and drain retrieves messages in order", %{session_id: session_id} do
      PendingQueue.enqueue(session_id, "first")
      PendingQueue.enqueue(session_id, "second")
      PendingQueue.enqueue(session_id, "third")

      assert PendingQueue.drain(session_id) == ["first", "second", "third"]
    end

    test "drain is atomic — second drain returns empty", %{session_id: session_id} do
      PendingQueue.enqueue(session_id, "msg")

      assert PendingQueue.drain(session_id) == ["msg"]
      assert PendingQueue.drain(session_id) == []
    end

    test "messages from different sessions are isolated", ctx do
      other_id = Ecto.UUID.generate()

      PendingQueue.enqueue(ctx.session_id, "for_session_a")
      PendingQueue.enqueue(other_id, "for_session_b")

      assert PendingQueue.drain(ctx.session_id) == ["for_session_a"]
      assert PendingQueue.drain(other_id) == ["for_session_b"]
    end
  end

  describe "pending?/1" do
    test "returns false when empty", %{session_id: session_id} do
      refute PendingQueue.pending?(session_id)
    end

    test "returns true when messages are queued", %{session_id: session_id} do
      PendingQueue.enqueue(session_id, "msg")
      assert PendingQueue.pending?(session_id)
    end

    test "returns false after drain", %{session_id: session_id} do
      PendingQueue.enqueue(session_id, "msg")
      PendingQueue.drain(session_id)
      refute PendingQueue.pending?(session_id)
    end
  end
end
