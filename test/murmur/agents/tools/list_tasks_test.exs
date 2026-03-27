defmodule Murmur.Agents.Tools.ListTasksTest do
  @moduledoc """
  Tests for the ListTasks agent tool.

  Covers:
  - Listing all tasks for a workspace
  - Filtering by status
  - Empty state messages
  - Formatted output with task details
  - Invalid status filter handling
  """
  use Murmur.DataCase

  alias Murmur.Agents.Tools.ListTasks
  alias Murmur.Tasks
  alias Murmur.Workspaces

  setup do
    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "ListTasks Test"})
    %{workspace: workspace}
  end

  describe "run/2 — empty board" do
    test "returns empty message when no tasks exist", %{workspace: workspace} do
      params = %{}
      context = %{workspace_id: workspace.id}

      assert {:ok, %{result: "No tasks on the board yet."}} = ListTasks.run(params, context)
    end

    test "returns filtered empty message when no tasks match status", %{workspace: workspace} do
      {:ok, _} = Tasks.create_task(workspace.id, %{title: "Todo task", assignee: "A"}, "X")

      params = %{status: "done"}
      context = %{workspace_id: workspace.id}

      assert {:ok, %{result: result}} = ListTasks.run(params, context)
      assert result =~ "No tasks with status"
    end
  end

  describe "run/2 — listing tasks" do
    test "lists all tasks with details", %{workspace: workspace} do
      {:ok, _} = Tasks.create_task(workspace.id, %{title: "First task", assignee: "Alice"}, "Bob")
      {:ok, _} = Tasks.create_task(workspace.id, %{title: "Second task", assignee: "Bob"}, "Alice")

      params = %{}
      context = %{workspace_id: workspace.id}

      assert {:ok, %{result: result}} = ListTasks.run(params, context)
      assert result =~ "2 task(s)"
      assert result =~ "First task"
      assert result =~ "Second task"
      assert result =~ "Alice"
      assert result =~ "Bob"
    end

    test "includes task description in output", %{workspace: workspace} do
      {:ok, _} =
        Tasks.create_task(
          workspace.id,
          %{title: "Detailed", description: "Some details here", assignee: "Alice"},
          "Bob"
        )

      params = %{}
      context = %{workspace_id: workspace.id}

      {:ok, %{result: result}} = ListTasks.run(params, context)
      assert result =~ "Some details here"
    end

    test "filters by status", %{workspace: workspace} do
      {:ok, _} = Tasks.create_task(workspace.id, %{title: "Todo", assignee: "A"}, "X")

      {:ok, wip} =
        Tasks.create_task(
          workspace.id,
          %{title: "In progress", assignee: "B", status: :in_progress},
          "X"
        )

      params = %{status: "in_progress"}
      context = %{workspace_id: workspace.id}

      {:ok, %{result: result}} = ListTasks.run(params, context)
      assert result =~ "1 task(s)"
      assert result =~ wip.title
      refute result =~ "Todo"
    end

    test "shows status in bracket notation", %{workspace: workspace} do
      {:ok, _} = Tasks.create_task(workspace.id, %{title: "My task", assignee: "A"}, "X")

      params = %{}
      context = %{workspace_id: workspace.id}

      {:ok, %{result: result}} = ListTasks.run(params, context)
      assert result =~ "[todo]"
    end

    test "shows task id in output", %{workspace: workspace} do
      {:ok, task} = Tasks.create_task(workspace.id, %{title: "ID check", assignee: "A"}, "X")

      params = %{}
      context = %{workspace_id: workspace.id}

      {:ok, %{result: result}} = ListTasks.run(params, context)
      assert result =~ task.id
    end
  end

  describe "run/2 — invalid status filter" do
    test "returns error for invalid status", %{workspace: workspace} do
      params = %{status: "not_a_status"}
      context = %{workspace_id: workspace.id}

      assert {:error, msg} = ListTasks.run(params, context)
      assert msg =~ "Invalid status filter"
    end
  end
end
