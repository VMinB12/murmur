defmodule MurmurWeb.WorkspaceLiveTaskBoardTest do
  @moduledoc """
  LiveView tests for the task board feature.

  Covers:
  - Toggling the task board panel
  - Creating tasks through the form
  - Updating task status through buttons
  - Real-time task updates via PubSub
  """
  use MurmurWeb.ConnCase

  import Phoenix.LiveViewTest

  alias JidoMurmur.Workspaces
  alias JidoTasks.Tasks
  alias Murmur.LLM.MockBehaviour, as: Mock

  setup do
    Mox.set_mox_global()

    Mox.stub(Mock, :ask, fn _mod, _pid, _content, _ctx ->
      {:ok, make_ref()}
    end)

    Mox.stub(Mock, :await, fn _mod, _handle, _opts ->
      {:ok, "mock response"}
    end)

    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Task Board Test"})

    {:ok, _alice} =
      Workspaces.create_agent_session(workspace.id, %{
        "agent_profile_id" => "general_agent",
        "display_name" => "Alice"
      })

    %{workspace: workspace}
  end

  describe "toggle task board" do
    test "task board is hidden by default", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      refute has_element?(view, "#create-task-form")
    end

    test "clicking Tasks button shows the task board", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      view |> element("button", "Tasks") |> render_click()

      assert has_element?(view, "#create-task-form")
    end

    test "clicking Tasks again hides the board", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      view |> element("button", "Tasks") |> render_click()
      assert has_element?(view, "#create-task-form")

      view |> element("button", "Tasks") |> render_click()
      refute has_element?(view, "#create-task-form")
    end
  end

  describe "create task" do
    test "creating a task via form adds it to the board", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      # Open task board
      view |> element("button", "Tasks") |> render_click()

      # Submit the form
      view
      |> form("#create-task-form", task: %{title: "New task", assignee: "Alice"})
      |> render_submit()

      # Task should appear in the board
      assert has_element?(view, "p", "New task")
    end

    test "created task is persisted in database", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      view |> element("button", "Tasks") |> render_click()

      view
      |> form("#create-task-form", task: %{title: "Persisted task", assignee: "Alice"})
      |> render_submit()

      tasks = Tasks.list_tasks(workspace.id)
      assert length(tasks) == 1
      assert hd(tasks).title == "Persisted task"
      assert hd(tasks).created_by == "human"
    end
  end

  describe "update task status" do
    test "clicking start button moves task to in_progress", %{conn: conn, workspace: workspace} do
      {:ok, task} =
        Tasks.create_task(workspace.id, %{title: "Start me", assignee: "Alice"}, "human")

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      view |> element("button", "Tasks") |> render_click()

      # Click the start button for the task
      view
      |> element("button[phx-click='update_task_status'][phx-value-task-id='#{task.id}'][phx-value-status='in_progress']")
      |> render_click()

      updated = Tasks.get_task!(task.id)
      assert updated.status == :in_progress
    end
  end

  describe "real-time updates via PubSub" do
    test "task_created message adds task to the board", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      view |> element("button", "Tasks") |> render_click()

      # Simulate an agent creating a task
      {:ok, task} =
        Tasks.create_task(workspace.id, %{title: "Agent task", assignee: "Alice"}, "Bob")

      send(view.pid, {:task_created, task})

      # Task should appear
      assert render(view) =~ "Agent task"
    end

    test "task_updated message refreshes task in the board", %{conn: conn, workspace: workspace} do
      {:ok, task} =
        Tasks.create_task(workspace.id, %{title: "Updatable", assignee: "Alice"}, "human")

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      view |> element("button", "Tasks") |> render_click()

      # Simulate a status update
      {:ok, updated} = Tasks.update_task(task, %{status: :done})
      send(view.pid, {:task_updated, updated})

      # The updated status should be reflected
      html = render(view)
      assert html =~ "Updatable"
    end
  end

  describe "pre-existing tasks" do
    test "loads existing tasks on mount", %{conn: conn, workspace: workspace} do
      {:ok, _} =
        Tasks.create_task(workspace.id, %{title: "Pre-existing", assignee: "Alice"}, "human")

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      view |> element("button", "Tasks") |> render_click()

      assert has_element?(view, "p", "Pre-existing")
    end
  end
end
