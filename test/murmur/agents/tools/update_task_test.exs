defmodule Murmur.Agents.Tools.UpdateTaskTest do
  @moduledoc """
  Tests for the UpdateTask agent tool.

  Covers:
  - Updating task status through the tool interface
  - Updating task title and description
  - PubSub broadcast of task_updated
  - Workspace ownership verification
  - Error handling for non-existent tasks
  """
  use Murmur.DataCase

  alias Murmur.Agents.Tools.UpdateTask
  alias Murmur.Tasks
  alias Murmur.Workspaces

  setup do
    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "UpdateTask Test"})

    {:ok, task} =
      Tasks.create_task(workspace.id, %{title: "Original title", assignee: "Alice"}, "Bob")

    %{workspace: workspace, task: task}
  end

  describe "run/2 — status updates" do
    test "updates task status to in_progress", %{workspace: workspace, task: task} do
      params = %{task_id: task.id, status: "in_progress"}
      context = %{workspace_id: workspace.id}

      assert {:ok, %{result: result}} = UpdateTask.run(params, context)
      assert result =~ "in_progress"
    end

    test "updates task status to done", %{workspace: workspace, task: task} do
      params = %{task_id: task.id, status: "done"}
      context = %{workspace_id: workspace.id}

      assert {:ok, %{result: result}} = UpdateTask.run(params, context)
      assert result =~ "done"
    end

    test "updates task status to aborted", %{workspace: workspace, task: task} do
      params = %{task_id: task.id, status: "aborted"}
      context = %{workspace_id: workspace.id}

      assert {:ok, %{result: result}} = UpdateTask.run(params, context)
      assert result =~ "aborted"
    end

    test "persists status change in database", %{workspace: workspace, task: task} do
      params = %{task_id: task.id, status: "done"}
      context = %{workspace_id: workspace.id}

      UpdateTask.run(params, context)

      updated = Tasks.get_task!(task.id)
      assert updated.status == :done
    end
  end

  describe "run/2 — field updates" do
    test "updates task title", %{workspace: workspace, task: task} do
      params = %{task_id: task.id, title: "New title"}
      context = %{workspace_id: workspace.id}

      assert {:ok, %{result: result}} = UpdateTask.run(params, context)
      assert result =~ "New title"
    end

    test "updates task description", %{workspace: workspace, task: task} do
      params = %{task_id: task.id, description: "Updated description"}
      context = %{workspace_id: workspace.id}

      {:ok, _} = UpdateTask.run(params, context)

      updated = Tasks.get_task!(task.id)
      assert updated.description == "Updated description"
    end
  end

  describe "run/2 — PubSub" do
    test "broadcasts task_updated", %{workspace: workspace, task: task} do
      Phoenix.PubSub.subscribe(Murmur.PubSub, Tasks.tasks_topic(workspace.id))

      params = %{task_id: task.id, status: "done"}
      context = %{workspace_id: workspace.id}

      {:ok, _} = UpdateTask.run(params, context)

      assert_receive {:task_updated, updated}
      assert updated.status == :done
    end
  end

  describe "run/2 — error cases" do
    test "returns error for non-existent task", %{workspace: workspace} do
      params = %{task_id: Ecto.UUID.generate(), status: "done"}
      context = %{workspace_id: workspace.id}

      assert {:error, msg} = UpdateTask.run(params, context)
      assert msg =~ "Task not found"
    end

    test "returns error for task in different workspace", %{task: task} do
      {:ok, other_ws} = Workspaces.create_workspace(%{"name" => "Other"})

      params = %{task_id: task.id, status: "done"}
      context = %{workspace_id: other_ws.id}

      assert {:error, msg} = UpdateTask.run(params, context)
      assert msg =~ "not found in this workspace"
    end

    test "raises for invalid status string", %{workspace: workspace, task: task} do
      params = %{task_id: task.id, status: "invalid_status"}
      context = %{workspace_id: workspace.id}

      assert_raise RuntimeError, ~r/Invalid status/, fn ->
        UpdateTask.run(params, context)
      end
    end
  end
end
