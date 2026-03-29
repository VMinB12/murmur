defmodule Murmur.TasksTest do
  @moduledoc """
  Tests for the Tasks context module.

  Covers:
  - Creating tasks in a workspace
  - Listing tasks with optional status filter
  - Updating task fields
  - Task stats aggregation
  - Deleting all tasks for a workspace
  """
  use Murmur.DataCase

  alias JidoMurmur.Workspaces
  alias JidoTasks.Task
  alias JidoTasks.Tasks

  setup do
    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Task Test"})
    %{workspace: workspace}
  end

  describe "create_task/3" do
    test "creates a task with valid attrs", %{workspace: workspace} do
      attrs = %{title: "Write docs", assignee: "Alice"}
      assert {:ok, %Task{} = task} = Tasks.create_task(workspace.id, attrs, "Bob")

      assert task.title == "Write docs"
      assert task.assignee == "Alice"
      assert task.created_by == "Bob"
      assert task.status == :todo
      assert task.workspace_id == workspace.id
    end

    test "creates a task with description", %{workspace: workspace} do
      attrs = %{title: "Research LLMs", description: "Compare models", assignee: "Alice"}
      assert {:ok, task} = Tasks.create_task(workspace.id, attrs, "Bob")
      assert task.description == "Compare models"
    end

    test "rejects task without title", %{workspace: workspace} do
      attrs = %{assignee: "Alice"}
      assert {:error, changeset} = Tasks.create_task(workspace.id, attrs, "Bob")
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects task without assignee", %{workspace: workspace} do
      attrs = %{title: "Do something"}
      assert {:error, changeset} = Tasks.create_task(workspace.id, attrs, "Bob")
      assert %{assignee: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects title exceeding 200 chars", %{workspace: workspace} do
      attrs = %{title: String.duplicate("a", 201), assignee: "Alice"}
      assert {:error, changeset} = Tasks.create_task(workspace.id, attrs, "Bob")
      assert %{title: [msg]} = errors_on(changeset)
      assert msg =~ "should be at most 200"
    end

    test "rejects description exceeding 2000 chars", %{workspace: workspace} do
      attrs = %{title: "Task", description: String.duplicate("a", 2001), assignee: "Alice"}
      assert {:error, changeset} = Tasks.create_task(workspace.id, attrs, "Bob")
      assert %{description: [msg]} = errors_on(changeset)
      assert msg =~ "should be at most 2000"
    end

    test "defaults status to :todo", %{workspace: workspace} do
      attrs = %{title: "Default status", assignee: "Alice"}
      {:ok, task} = Tasks.create_task(workspace.id, attrs, "Bob")
      assert task.status == :todo
    end
  end

  describe "list_tasks/2" do
    test "returns empty list for workspace with no tasks", %{workspace: workspace} do
      assert Tasks.list_tasks(workspace.id) == []
    end

    test "returns all tasks ordered by inserted_at", %{workspace: workspace} do
      {:ok, t1} = Tasks.create_task(workspace.id, %{title: "First", assignee: "A"}, "X")
      {:ok, t2} = Tasks.create_task(workspace.id, %{title: "Second", assignee: "B"}, "X")
      {:ok, t3} = Tasks.create_task(workspace.id, %{title: "Third", assignee: "C"}, "X")

      tasks = Tasks.list_tasks(workspace.id)
      assert [^t1, ^t2, ^t3] = tasks
    end

    test "filters by status", %{workspace: workspace} do
      {:ok, _} = Tasks.create_task(workspace.id, %{title: "Todo", assignee: "A"}, "X")

      {:ok, in_progress} =
        Tasks.create_task(workspace.id, %{title: "WIP", assignee: "B", status: :in_progress}, "X")

      tasks = Tasks.list_tasks(workspace.id, status: :in_progress)
      assert [^in_progress] = tasks
    end

    test "isolates tasks between workspaces", %{workspace: workspace} do
      {:ok, other_ws} = Workspaces.create_workspace(%{"name" => "Other"})
      {:ok, _} = Tasks.create_task(workspace.id, %{title: "Mine", assignee: "A"}, "X")
      {:ok, _} = Tasks.create_task(other_ws.id, %{title: "Theirs", assignee: "B"}, "X")

      tasks = Tasks.list_tasks(workspace.id)
      assert length(tasks) == 1
      assert hd(tasks).title == "Mine"
    end
  end

  describe "get_task!/1 and get_task/1" do
    test "get_task! returns task by id", %{workspace: workspace} do
      {:ok, task} = Tasks.create_task(workspace.id, %{title: "Get me", assignee: "A"}, "X")
      assert Tasks.get_task!(task.id).id == task.id
    end

    test "get_task! raises for non-existent id" do
      assert_raise Ecto.NoResultsError, fn ->
        Tasks.get_task!(Ecto.UUID.generate())
      end
    end

    test "get_task returns nil for non-existent id" do
      assert Tasks.get_task(Ecto.UUID.generate()) == nil
    end

    test "get_task returns task by id", %{workspace: workspace} do
      {:ok, task} = Tasks.create_task(workspace.id, %{title: "Nullable", assignee: "A"}, "X")
      assert Tasks.get_task(task.id).id == task.id
    end
  end

  describe "update_task/2" do
    test "updates status", %{workspace: workspace} do
      {:ok, task} = Tasks.create_task(workspace.id, %{title: "Update me", assignee: "A"}, "X")
      assert {:ok, updated} = Tasks.update_task(task, %{status: :in_progress})
      assert updated.status == :in_progress
    end

    test "updates title", %{workspace: workspace} do
      {:ok, task} = Tasks.create_task(workspace.id, %{title: "Old title", assignee: "A"}, "X")
      assert {:ok, updated} = Tasks.update_task(task, %{title: "New title"})
      assert updated.title == "New title"
    end

    test "updates description", %{workspace: workspace} do
      {:ok, task} = Tasks.create_task(workspace.id, %{title: "Desc", assignee: "A"}, "X")
      assert {:ok, updated} = Tasks.update_task(task, %{description: "Added details"})
      assert updated.description == "Added details"
    end

    test "rejects invalid status", %{workspace: workspace} do
      {:ok, task} = Tasks.create_task(workspace.id, %{title: "Bad status", assignee: "A"}, "X")
      assert {:error, changeset} = Tasks.update_task(task, %{status: :invalid})
      assert %{status: _} = errors_on(changeset)
    end

    test "does not allow updating assignee", %{workspace: workspace} do
      {:ok, task} = Tasks.create_task(workspace.id, %{title: "No reassign", assignee: "A"}, "X")
      {:ok, updated} = Tasks.update_task(task, %{assignee: "B"})
      # assignee is not in update_changeset's cast, so it stays unchanged
      assert updated.assignee == "A"
    end
  end

  describe "task_stats/1" do
    test "returns empty map for workspace with no tasks", %{workspace: workspace} do
      assert Tasks.task_stats(workspace.id) == %{}
    end

    test "returns counts grouped by status", %{workspace: workspace} do
      {:ok, _} = Tasks.create_task(workspace.id, %{title: "T1", assignee: "A"}, "X")
      {:ok, _} = Tasks.create_task(workspace.id, %{title: "T2", assignee: "B"}, "X")
      {:ok, t3} = Tasks.create_task(workspace.id, %{title: "T3", assignee: "C"}, "X")
      Tasks.update_task(t3, %{status: :done})

      stats = Tasks.task_stats(workspace.id)
      assert stats[:todo] == 2
      assert stats[:done] == 1
    end
  end

  describe "delete_tasks_for_workspace/1" do
    test "deletes all tasks in the workspace", %{workspace: workspace} do
      {:ok, _} = Tasks.create_task(workspace.id, %{title: "T1", assignee: "A"}, "X")
      {:ok, _} = Tasks.create_task(workspace.id, %{title: "T2", assignee: "B"}, "X")

      assert {2, nil} = Tasks.delete_tasks_for_workspace(workspace.id)
      assert Tasks.list_tasks(workspace.id) == []
    end

    test "does not affect other workspaces", %{workspace: workspace} do
      {:ok, other} = Workspaces.create_workspace(%{"name" => "Other"})
      {:ok, _} = Tasks.create_task(workspace.id, %{title: "Mine", assignee: "A"}, "X")
      {:ok, _} = Tasks.create_task(other.id, %{title: "Theirs", assignee: "B"}, "X")

      Tasks.delete_tasks_for_workspace(workspace.id)
      assert other.id |> Tasks.list_tasks() |> length() == 1
    end
  end

  describe "tasks_topic/1" do
    test "returns expected topic string" do
      id = Ecto.UUID.generate()
      assert Tasks.tasks_topic(id) == "workspace:#{id}:tasks"
    end
  end
end
