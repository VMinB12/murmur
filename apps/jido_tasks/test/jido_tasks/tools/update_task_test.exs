defmodule JidoTasks.Tools.UpdateTaskTest do
  use JidoTasks.Case, async: true

  alias JidoTasks.Tasks
  alias JidoTasks.Tools.UpdateTask

  setup do
    {:ok, workspace} =
      JidoTasks.repo().insert(%JidoMurmur.Workspaces.Workspace{name: "update-task-test"})

    {:ok, task} =
      Tasks.create_task(workspace.id, %{title: "Initial task", assignee: "agent-a"}, "creator")

    context = %{workspace_id: workspace.id, sender_name: "test-agent"}
    %{workspace_id: workspace.id, task: task, context: context}
  end

  describe "status transitions" do
    test "todo -> in_progress", %{task: task, context: context} do
      params = %{task_id: task.id, status: "in_progress"}
      assert {:ok, %{result: result}} = UpdateTask.run(params, context)
      assert result =~ "in_progress"
    end

    test "todo -> done", %{task: task, context: context} do
      params = %{task_id: task.id, status: "done"}
      assert {:ok, %{result: result}} = UpdateTask.run(params, context)
      assert result =~ "done"
    end

    test "todo -> aborted", %{task: task, context: context} do
      params = %{task_id: task.id, status: "aborted"}
      assert {:ok, %{result: result}} = UpdateTask.run(params, context)
      assert result =~ "aborted"
    end

    test "in_progress -> done", %{task: task, context: context} do
      Tasks.update_task(task, %{status: :in_progress})

      params = %{task_id: task.id, status: "done"}
      assert {:ok, %{result: result}} = UpdateTask.run(params, context)
      assert result =~ "done"
    end

    test "raises on invalid status string", %{task: task, context: context} do
      params = %{task_id: task.id, status: "invalid_status"}

      assert_raise RuntimeError, ~r/Invalid status/, fn ->
        UpdateTask.run(params, context)
      end
    end
  end

  describe "error cases" do
    test "returns error for nonexistent task_id", %{context: context} do
      params = %{task_id: Ecto.UUID.generate(), status: "done"}
      assert {:error, msg} = UpdateTask.run(params, context)
      assert msg =~ "Task not found"
    end

    test "returns error for task in different workspace", %{task: task} do
      other_context = %{workspace_id: Ecto.UUID.generate(), sender_name: "other"}
      params = %{task_id: task.id, status: "done"}

      assert {:error, msg} = UpdateTask.run(params, other_context)
      assert msg =~ "not found in this workspace"
    end
  end

  describe "field updates" do
    test "updates title", %{task: task, context: context} do
      params = %{task_id: task.id, title: "Updated title"}
      assert {:ok, %{result: result}} = UpdateTask.run(params, context)
      assert result =~ "Updated title"
    end

    test "updates description", %{task: task, context: context} do
      params = %{task_id: task.id, description: "New description"}
      assert {:ok, %{result: result}} = UpdateTask.run(params, context)
      assert result =~ "Initial task"
    end

    test "updates multiple fields at once", %{task: task, context: context} do
      params = %{task_id: task.id, title: "New title", status: "in_progress"}
      assert {:ok, %{result: result}} = UpdateTask.run(params, context)
      assert result =~ "New title"
      assert result =~ "in_progress"
    end
  end

  describe "PubSub broadcast" do
    test "broadcasts :task_updated on tasks topic", %{
      workspace_id: workspace_id,
      task: task,
      context: context
    } do
      topic = Tasks.tasks_topic(workspace_id)
      Phoenix.PubSub.subscribe(JidoTasks.pubsub(), topic)

      params = %{task_id: task.id, status: "done"}
      {:ok, _} = UpdateTask.run(params, context)

      assert_receive {:task_updated, updated}
      assert updated.status == :done
    end
  end
end
