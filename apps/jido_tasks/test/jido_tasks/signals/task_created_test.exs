defmodule JidoTasks.Signals.TaskCreatedTest do
  use ExUnit.Case, async: true

  alias JidoTasks.Signals.TaskCreated
  alias JidoTasks.Task

  describe "new/2" do
    test "creates signal with correct type and source" do
      task = %Task{id: "42", title: "Test task", status: :todo}
      {:ok, signal} = TaskCreated.new(%{task: task})

      assert signal.type == "task.created"
      assert signal.source == "/jido_tasks/tools/add_task"
      assert signal.data.task == task
      assert signal.id
    end

    test "creates signal with subject override" do
      task = %Task{id: "42", title: "Test task", status: :todo}
      subject = TaskCreated.subject("ws_1", "42")

      {:ok, signal} = TaskCreated.new(%{task: task}, subject: subject)

      assert signal.subject == "/workspaces/ws_1/tasks/42"
    end

    test "rejects missing task" do
      assert {:error, _} = TaskCreated.new(%{})
    end

    test "rejects non-task payloads" do
      assert {:error, _} = TaskCreated.new(%{task: %{id: "42", title: "Test task"}})
    end
  end

  describe "subject/2" do
    test "builds correct subject URI" do
      assert TaskCreated.subject("ws_1", "42") == "/workspaces/ws_1/tasks/42"
    end
  end
end
