defmodule JidoTasks.TasksTelemetryTest do
  use JidoTasks.Case, async: false

  alias JidoTasks.Tasks

  setup do
    {:ok, workspace} =
      JidoTasks.repo().insert(%JidoMurmur.Workspaces.Workspace{name: "telemetry-test"})

    ref = make_ref()
    pid = self()

    :telemetry.attach_many(
      "test-tasks-#{inspect(ref)}",
      [
        [:jido_tasks, :task, :create, :stop],
        [:jido_tasks, :task, :update, :stop],
        [:jido_tasks, :task, :list, :stop]
      ],
      fn event, measurements, metadata, _config ->
        send(pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach("test-tasks-#{inspect(ref)}") end)
    %{workspace_id: workspace.id}
  end

  describe "task create telemetry" do
    test "emits [:jido_tasks, :task, :create, :stop] with duration and task_id", %{workspace_id: workspace_id} do
      {:ok, task} =
        Tasks.create_task(workspace_id, %{title: "Tele task", assignee: "bot", status: :todo}, "tester")

      assert_receive {:telemetry, [:jido_tasks, :task, :create, :stop], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.task_id == task.id
      assert metadata.workspace_id == workspace_id
    end
  end

  describe "task update telemetry" do
    test "emits [:jido_tasks, :task, :update, :stop] with old_status and new_status", %{workspace_id: workspace_id} do
      {:ok, task} =
        Tasks.create_task(workspace_id, %{title: "Update tele", assignee: "bot", status: :todo}, "tester")

      # Drain create event
      assert_receive {:telemetry, [:jido_tasks, :task, :create, :stop], _, _}

      {:ok, _updated} = Tasks.update_task(task, %{status: :in_progress})

      assert_receive {:telemetry, [:jido_tasks, :task, :update, :stop], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.task_id == task.id
      assert metadata.old_status == :todo
      assert metadata.new_status == :in_progress
    end
  end

  describe "task list telemetry" do
    test "emits [:jido_tasks, :task, :list, :stop] with count", %{workspace_id: workspace_id} do
      {:ok, _} =
        Tasks.create_task(workspace_id, %{title: "List tele 1", assignee: "bot", status: :todo}, "tester")

      {:ok, _} =
        Tasks.create_task(workspace_id, %{title: "List tele 2", assignee: "bot", status: :todo}, "tester")

      # Drain create events
      assert_receive {:telemetry, [:jido_tasks, :task, :create, :stop], _, _}
      assert_receive {:telemetry, [:jido_tasks, :task, :create, :stop], _, _}

      _tasks = Tasks.list_tasks(workspace_id)

      assert_receive {:telemetry, [:jido_tasks, :task, :list, :stop], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.workspace_id == workspace_id
      assert metadata.count >= 2
    end
  end
end
