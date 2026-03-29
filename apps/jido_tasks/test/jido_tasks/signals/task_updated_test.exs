defmodule JidoTasks.Signals.TaskUpdatedTest do
  use ExUnit.Case, async: true

  alias JidoTasks.Signals.TaskUpdated

  describe "new/2" do
    test "creates signal with correct type and source" do
      task = %{id: "42", title: "Test task", status: :done}
      {:ok, signal} = TaskUpdated.new(%{task: task})

      assert signal.type == "task.updated"
      assert signal.source == "/jido_tasks/tools/update_task"
      assert signal.data.task == task
      assert signal.id != nil
    end

    test "creates signal with subject override" do
      task = %{id: "42", title: "Test task"}
      subject = TaskUpdated.subject("ws_1", "42")

      {:ok, signal} = TaskUpdated.new(%{task: task}, subject: subject)

      assert signal.subject == "/workspaces/ws_1/tasks/42"
    end

    test "rejects missing task" do
      assert {:error, _} = TaskUpdated.new(%{})
    end
  end

  describe "subject/2" do
    test "builds correct subject URI" do
      assert TaskUpdated.subject("ws_1", "42") == "/workspaces/ws_1/tasks/42"
    end
  end
end
