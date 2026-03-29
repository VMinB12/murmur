defmodule JidoTasks.Tools.ToolTest do
  use JidoTasks.Case, async: true

  alias JidoTasks.Tasks
  alias JidoTasks.Tools.AddTask
  alias JidoTasks.Tools.ListTasks
  alias JidoTasks.Tools.UpdateTask

  setup do
    {:ok, workspace} =
      JidoTasks.repo().insert(%JidoMurmur.Workspaces.Workspace{name: "tool-test"})

    context = %{workspace_id: workspace.id, sender_name: "test-agent"}
    %{workspace_id: workspace.id, context: context}
  end

  describe "AddTask" do
    test "creates a task and returns success message", %{context: context} do
      params = %{title: "Write docs", assignee: "human"}
      assert {:ok, %{result: result}} = AddTask.run(params, context)

      assert result =~ "Task created"
      assert result =~ "Write docs"
      assert result =~ "human"
    end

    test "creates a task with description", %{context: context} do
      params = %{title: "Research", assignee: "other-agent", description: "Deep dive"}
      assert {:ok, %{result: result}} = AddTask.run(params, context)

      assert result =~ "Research"
    end

    test "fails with missing title", %{context: context} do
      params = %{assignee: "human"}
      assert {:error, msg} = AddTask.run(params, context)

      assert msg =~ "Failed to create task"
    end

    test "broadcasts task_created via PubSub", %{workspace_id: workspace_id, context: context} do
      topic = Tasks.tasks_topic(workspace_id)
      Phoenix.PubSub.subscribe(JidoTasks.pubsub(), topic)

      params = %{title: "Notify test", assignee: "human"}
      assert {:ok, _} = AddTask.run(params, context)

      assert_receive {:task_created, task}
      assert task.title == "Notify test"
    end

    test "includes board stats in result", %{workspace_id: workspace_id, context: context} do
      Tasks.create_task(workspace_id, %{title: "Existing", assignee: "A"}, "C")

      params = %{title: "New task", assignee: "human"}
      assert {:ok, %{result: result}} = AddTask.run(params, context)

      assert result =~ "2 task(s)"
    end
  end

  describe "UpdateTask" do
    test "updates task status", %{workspace_id: workspace_id, context: context} do
      {:ok, task} = Tasks.create_task(workspace_id, %{title: "T", assignee: "A"}, "C")

      params = %{task_id: task.id, status: "in_progress"}
      assert {:ok, %{result: result}} = UpdateTask.run(params, context)

      assert result =~ "in_progress"
    end

    test "updates task title", %{workspace_id: workspace_id, context: context} do
      {:ok, task} = Tasks.create_task(workspace_id, %{title: "Old", assignee: "A"}, "C")

      params = %{task_id: task.id, title: "New title"}
      assert {:ok, %{result: result}} = UpdateTask.run(params, context)

      assert result =~ "New title"
    end

    test "returns error for missing task", %{context: context} do
      params = %{task_id: Ecto.UUID.generate(), status: "done"}
      assert {:error, msg} = UpdateTask.run(params, context)

      assert msg =~ "Task not found"
    end

    test "returns error for task in different workspace", %{context: _context} do
      {:ok, other_ws} =
        JidoTasks.repo().insert(%JidoMurmur.Workspaces.Workspace{name: "other"})

      {:ok, task} = Tasks.create_task(other_ws.id, %{title: "T", assignee: "A"}, "C")

      other_context = %{workspace_id: Ecto.UUID.generate(), sender_name: "agent"}
      params = %{task_id: task.id, status: "done"}
      assert {:error, msg} = UpdateTask.run(params, other_context)

      assert msg =~ "not found in this workspace"
    end

    test "broadcasts task_updated via PubSub", %{workspace_id: workspace_id, context: context} do
      {:ok, task} = Tasks.create_task(workspace_id, %{title: "T", assignee: "A"}, "C")
      topic = Tasks.tasks_topic(workspace_id)
      Phoenix.PubSub.subscribe(JidoTasks.pubsub(), topic)

      params = %{task_id: task.id, status: "done"}
      assert {:ok, _} = UpdateTask.run(params, context)

      assert_receive {:task_updated, updated}
      assert updated.status == :done
    end

    test "raises on invalid status", %{workspace_id: workspace_id, context: context} do
      {:ok, task} = Tasks.create_task(workspace_id, %{title: "T", assignee: "A"}, "C")

      params = %{task_id: task.id, status: "invalid"}

      assert_raise RuntimeError, ~r/Invalid status/, fn ->
        UpdateTask.run(params, context)
      end
    end
  end

  describe "ListTasks" do
    test "lists all workspace tasks", %{workspace_id: workspace_id, context: context} do
      Tasks.create_task(workspace_id, %{title: "Task 1", assignee: "A"}, "C")
      Tasks.create_task(workspace_id, %{title: "Task 2", assignee: "B"}, "C")

      assert {:ok, %{result: result}} = ListTasks.run(%{}, context)

      assert result =~ "2 task(s)"
      assert result =~ "Task 1"
      assert result =~ "Task 2"
    end

    test "filters by status", %{workspace_id: workspace_id, context: context} do
      {:ok, task} = Tasks.create_task(workspace_id, %{title: "Done T", assignee: "A"}, "C")
      Tasks.update_task(task, %{status: :done})
      Tasks.create_task(workspace_id, %{title: "Todo T", assignee: "B"}, "C")

      assert {:ok, %{result: result}} = ListTasks.run(%{status: "todo"}, context)

      assert result =~ "1 task(s)"
      assert result =~ "Todo T"
      refute result =~ "Done T"
    end

    test "returns empty message when no tasks", %{context: context} do
      assert {:ok, %{result: result}} = ListTasks.run(%{}, context)

      assert result =~ "No tasks on the board yet"
    end

    test "returns empty message for filtered empty", %{context: context} do
      assert {:ok, %{result: result}} = ListTasks.run(%{status: "done"}, context)

      assert result =~ "No tasks with status"
    end

    test "returns error for invalid status filter", %{context: context} do
      assert {:error, msg} = ListTasks.run(%{status: "invalid"}, context)

      assert msg =~ "Invalid status filter"
    end

    test "includes description in output", %{workspace_id: workspace_id, context: context} do
      Tasks.create_task(
        workspace_id,
        %{title: "With desc", assignee: "A", description: "Some detail"},
        "C"
      )

      assert {:ok, %{result: result}} = ListTasks.run(%{}, context)

      assert result =~ "Some detail"
    end
  end
end
