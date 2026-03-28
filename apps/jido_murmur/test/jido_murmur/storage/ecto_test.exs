defmodule JidoMurmur.Storage.EctoTest do
  use JidoMurmur.Case, async: true

  alias JidoMurmur.Storage.Ecto, as: StorageEcto

  describe "checkpoints" do
    test "put and get a checkpoint" do
      key = "test-agent-#{Ecto.UUID.generate()}"
      data = %{state: "some_state", count: 42}

      assert :ok = StorageEcto.put_checkpoint(key, data, [])
      assert {:ok, retrieved} = StorageEcto.get_checkpoint(key, [])
      assert retrieved.state == "some_state"
      assert retrieved.count == 42
    end

    test "get returns :not_found for missing checkpoint" do
      assert :not_found = StorageEcto.get_checkpoint("nonexistent-key", [])
    end

    test "put overwrites existing checkpoint" do
      key = "test-agent-#{Ecto.UUID.generate()}"

      assert :ok = StorageEcto.put_checkpoint(key, %{version: 1}, [])
      assert :ok = StorageEcto.put_checkpoint(key, %{version: 2}, [])
      assert {:ok, retrieved} = StorageEcto.get_checkpoint(key, [])
      assert retrieved.version == 2
    end

    test "delete removes a checkpoint" do
      key = "test-agent-#{Ecto.UUID.generate()}"
      StorageEcto.put_checkpoint(key, %{data: true}, [])

      assert :ok = StorageEcto.delete_checkpoint(key, [])
      assert :not_found = StorageEcto.get_checkpoint(key, [])
    end

    test "delete is idempotent for missing keys" do
      assert :ok = StorageEcto.delete_checkpoint("never-existed", [])
    end
  end

  describe "threads" do
    test "append and load thread entries" do
      thread_id = "thread-#{Ecto.UUID.generate()}"

      entries = [
        %{kind: :message, payload: %{role: "user", content: "hello"}, refs: %{}}
      ]

      assert {:ok, thread} = StorageEcto.append_thread(thread_id, entries, [])
      assert thread.id == thread_id
      assert length(thread.entries) == 1
    end

    test "load returns :not_found for empty thread" do
      assert :not_found = StorageEcto.load_thread("nonexistent-thread", [])
    end

    test "append multiple batches preserves ordering" do
      thread_id = "thread-#{Ecto.UUID.generate()}"

      entries1 = [%{kind: :message, payload: %{role: "user", content: "first"}, refs: %{}}]
      entries2 = [%{kind: :ai_message, payload: %{role: "assistant", content: "second"}, refs: %{}}]

      assert {:ok, _} = StorageEcto.append_thread(thread_id, entries1, [])
      assert {:ok, thread} = StorageEcto.append_thread(thread_id, entries2, [])
      assert length(thread.entries) == 2

      [first, second] = thread.entries
      assert first.payload["role"] == "user"
      assert second.payload["role"] == "assistant"
    end

    test "delete removes all thread entries" do
      thread_id = "thread-#{Ecto.UUID.generate()}"
      entries = [%{kind: :message, payload: %{role: "user", content: "hello"}, refs: %{}}]
      StorageEcto.append_thread(thread_id, entries, [])

      assert :ok = StorageEcto.delete_thread(thread_id, [])
      assert :not_found = StorageEcto.load_thread(thread_id, [])
    end

    test "append with expected_rev conflict returns error" do
      thread_id = "thread-#{Ecto.UUID.generate()}"
      entries = [%{kind: :message, payload: %{role: "user", content: "hello"}, refs: %{}}]
      StorageEcto.append_thread(thread_id, entries, [])

      # There's 1 entry now, but we say expected 0
      assert {:error, :conflict} =
               StorageEcto.append_thread(thread_id, entries, expected_rev: 0)
    end
  end
end
