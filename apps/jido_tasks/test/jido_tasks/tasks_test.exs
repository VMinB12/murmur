defmodule JidoTasks.TasksTest do
  use JidoTasks.Case, async: true

  alias JidoTasks.Tasks

  setup do
    # Create a workspace for the tests
    {:ok, workspace} =
      JidoTasks.repo().insert(%JidoMurmur.Workspaces.Workspace{
        name: "test-workspace"
      })

    %{workspace_id: workspace.id}
  end

  describe "create_task/3" do
    test "creates a task with valid attrs", %{workspace_id: workspace_id} do
      attrs = %{title: "Fix bug", assignee: "agent-1"}
      assert {:ok, task} = Tasks.create_task(workspace_id, attrs, "creator")

      assert task.title == "Fix bug"
      assert task.assignee == "agent-1"
      assert task.created_by == "creator"
      assert task.workspace_id == workspace_id
      assert task.status == :todo
    end

    test "creates a task with description", %{workspace_id: workspace_id} do
      attrs = %{title: "Research topic", assignee: "agent-2", description: "Look into X"}
      assert {:ok, task} = Tasks.create_task(workspace_id, attrs, "creator")

      assert task.description == "Look into X"
    end

    test "fails without required title", %{workspace_id: workspace_id} do
      attrs = %{assignee: "agent-1"}
      assert {:error, changeset} = Tasks.create_task(workspace_id, attrs, "creator")

      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "fails without required assignee", %{workspace_id: workspace_id} do
      attrs = %{title: "A task"}
      assert {:error, changeset} = Tasks.create_task(workspace_id, attrs, "creator")

      assert %{assignee: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates title max length", %{workspace_id: workspace_id} do
      attrs = %{title: String.duplicate("x", 201), assignee: "agent-1"}
      assert {:error, changeset} = Tasks.create_task(workspace_id, attrs, "creator")

      assert %{title: [_]} = errors_on(changeset)
    end
  end

  describe "update_task/2" do
    test "updates task status", %{workspace_id: workspace_id} do
      {:ok, task} = Tasks.create_task(workspace_id, %{title: "T", assignee: "A"}, "C")
      assert {:ok, updated} = Tasks.update_task(task, %{status: :in_progress})

      assert updated.status == :in_progress
    end

    test "updates task title", %{workspace_id: workspace_id} do
      {:ok, task} = Tasks.create_task(workspace_id, %{title: "Old", assignee: "A"}, "C")
      assert {:ok, updated} = Tasks.update_task(task, %{title: "New"})

      assert updated.title == "New"
    end

    test "updates task description", %{workspace_id: workspace_id} do
      {:ok, task} = Tasks.create_task(workspace_id, %{title: "T", assignee: "A"}, "C")
      assert {:ok, updated} = Tasks.update_task(task, %{description: "Details"})

      assert updated.description == "Details"
    end
  end

  describe "list_tasks/2" do
    test "lists tasks for a workspace", %{workspace_id: workspace_id} do
      {:ok, _} = Tasks.create_task(workspace_id, %{title: "T1", assignee: "A"}, "C")
      {:ok, _} = Tasks.create_task(workspace_id, %{title: "T2", assignee: "B"}, "C")

      tasks = Tasks.list_tasks(workspace_id)
      assert length(tasks) == 2
    end

    test "filters by status", %{workspace_id: workspace_id} do
      {:ok, task} = Tasks.create_task(workspace_id, %{title: "T1", assignee: "A"}, "C")
      {:ok, _} = Tasks.update_task(task, %{status: :done})
      {:ok, _} = Tasks.create_task(workspace_id, %{title: "T2", assignee: "B"}, "C")

      todo_tasks = Tasks.list_tasks(workspace_id, status: :todo)
      assert length(todo_tasks) == 1
      assert hd(todo_tasks).title == "T2"
    end

    test "returns empty for workspace with no tasks", %{workspace_id: _workspace_id} do
      {:ok, other} =
        JidoTasks.repo().insert(%JidoMurmur.Workspaces.Workspace{name: "empty"})

      assert Tasks.list_tasks(other.id) == []
    end
  end

  describe "get_task!/1 and get_task/1" do
    test "get_task! returns a task by id", %{workspace_id: workspace_id} do
      {:ok, task} = Tasks.create_task(workspace_id, %{title: "T", assignee: "A"}, "C")

      found = Tasks.get_task!(task.id)
      assert found.id == task.id
    end

    test "get_task! raises for missing id", %{workspace_id: _workspace_id} do
      assert_raise Ecto.NoResultsError, fn ->
        Tasks.get_task!(Ecto.UUID.generate())
      end
    end

    test "get_task returns nil for missing id", %{workspace_id: _workspace_id} do
      assert Tasks.get_task(Ecto.UUID.generate()) == nil
    end
  end

  describe "task_stats/1" do
    test "returns status counts", %{workspace_id: workspace_id} do
      {:ok, t1} = Tasks.create_task(workspace_id, %{title: "T1", assignee: "A"}, "C")
      {:ok, _} = Tasks.create_task(workspace_id, %{title: "T2", assignee: "B"}, "C")
      {:ok, _} = Tasks.update_task(t1, %{status: :done})

      stats = Tasks.task_stats(workspace_id)
      assert Map.get(stats, :todo, 0) == 1
      assert Map.get(stats, :done, 0) == 1
    end

    test "returns empty map for no tasks", %{workspace_id: _workspace_id} do
      {:ok, other} =
        JidoTasks.repo().insert(%JidoMurmur.Workspaces.Workspace{name: "empty"})

      assert Tasks.task_stats(other.id) == %{}
    end
  end

  describe "delete_tasks_for_workspace/1" do
    test "deletes all tasks", %{workspace_id: workspace_id} do
      {:ok, _} = Tasks.create_task(workspace_id, %{title: "T1", assignee: "A"}, "C")
      {:ok, _} = Tasks.create_task(workspace_id, %{title: "T2", assignee: "B"}, "C")

      assert {2, nil} = Tasks.delete_tasks_for_workspace(workspace_id)
      assert Tasks.list_tasks(workspace_id) == []
    end
  end

  describe "tasks_topic/1" do
    test "returns PubSub topic string" do
      id = Ecto.UUID.generate()
      assert Tasks.tasks_topic(id) == "workspace:#{id}:tasks"
    end
  end

  defp errors_on(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
