defmodule JidoTasks.Tools.AddTaskTest do
  use JidoTasks.Case, async: true

  alias JidoTasks.Tasks
  alias JidoTasks.Tools.AddTask

  setup do
    {:ok, workspace} =
      JidoTasks.repo().insert(%JidoMurmur.Workspaces.Workspace{name: "add-task-test"})

    context = %{workspace_id: workspace.id, sender_name: "test-agent"}
    %{workspace_id: workspace.id, context: context}
  end

  describe "param validation" do
    test "requires title", %{context: context} do
      params = %{assignee: "human"}
      assert {:error, msg} = AddTask.run(params, context)
      assert msg =~ "Failed to create task"
    end

    test "creates task with minimal params (title + assignee)", %{context: context} do
      params = %{title: "Simple task", assignee: "human"}
      assert {:ok, %{result: result}} = AddTask.run(params, context)
      assert result =~ "Simple task"
    end

    test "creates task with all params", %{context: context} do
      params = %{title: "Full task", assignee: "agent-x", description: "Detailed description"}
      assert {:ok, %{result: result}} = AddTask.run(params, context)
      assert result =~ "Full task"
      assert result =~ "agent-x"
    end
  end

  describe "task creation" do
    test "sets status to :todo by default", %{workspace_id: workspace_id, context: context} do
      params = %{title: "New task", assignee: "human"}
      {:ok, _result} = AddTask.run(params, context)

      [task] = Tasks.list_tasks(workspace_id)
      assert task.status == :todo
    end

    test "sets created_by from sender context", %{workspace_id: workspace_id, context: context} do
      params = %{title: "Created by test", assignee: "human"}
      {:ok, _result} = AddTask.run(params, context)

      [task] = Tasks.list_tasks(workspace_id)
      assert task.created_by == "test-agent"
    end

    test "result includes board stats", %{workspace_id: workspace_id, context: context} do
      Tasks.create_task(workspace_id, %{title: "Existing", assignee: "A"}, "creator")

      params = %{title: "Another", assignee: "human"}
      {:ok, %{result: result}} = AddTask.run(params, context)

      assert result =~ "2 task(s)"
      assert result =~ "todo"
    end
  end

  describe "PubSub broadcasts" do
    test "broadcasts :task_created on tasks topic", %{workspace_id: workspace_id, context: context} do
      topic = Tasks.tasks_topic(workspace_id)
      Phoenix.PubSub.subscribe(JidoTasks.pubsub(), topic)

      params = %{title: "Broadcast test", assignee: "human"}
      {:ok, _result} = AddTask.run(params, context)

      assert_receive %Jido.Signal{type: "task.created", data: %{task: task}}
      assert task.title == "Broadcast test"
    end
  end

  describe "assignee notification" do
    test "does not notify when assigned to human", %{context: context} do
      params = %{title: "Human task", assignee: "human"}
      # Should succeed without error even though no agent is running
      assert {:ok, _} = AddTask.run(params, context)
    end

    test "does not notify when assigned to sender", %{context: context} do
      params = %{title: "Self-assigned", assignee: "test-agent"}
      assert {:ok, _} = AddTask.run(params, context)
    end
  end
end
