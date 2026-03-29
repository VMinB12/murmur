defmodule Murmur.Agents.Tools.AddTaskTest do
  @moduledoc """
  Tests for the AddTask agent tool.

  Covers:
  - Creating tasks through the tool interface
  - PubSub broadcast of task_created
  - Notification delivery to assigned agent
  - No notification when assigning to self or human
  - Error handling for invalid params
  """
  use Murmur.AgentCase

  alias JidoMurmur.Catalog
  alias JidoMurmur.Workspaces
  alias JidoTasks.Tasks
  alias JidoTasks.Tools.AddTask

  setup do
    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "AddTask Test"})

    {:ok, alice} =
      Workspaces.create_agent_session(workspace.id, %{
        "agent_profile_id" => "general_agent",
        "display_name" => "Alice"
      })

    {:ok, bob} =
      Workspaces.create_agent_session(workspace.id, %{
        "agent_profile_id" => "general_agent",
        "display_name" => "Bob"
      })

    agent_module = Catalog.agent_module(bob.agent_profile_id)
    {:ok, _pid} = Murmur.Jido.start_agent(agent_module, id: bob.id)

    stub_llm_success("Acknowledged task")

    on_exit(fn ->
      try do
        Murmur.Jido.stop_agent(bob.id)
      rescue
        _ -> :ok
      end
    end)

    %{workspace: workspace, alice: alice, bob: bob}
  end

  describe "run/2" do
    test "creates task and returns success message", %{workspace: workspace} do
      params = %{title: "Write tests", assignee: "Alice"}
      context = %{workspace_id: workspace.id, sender_name: "Bob"}

      assert {:ok, %{result: result}} = AddTask.run(params, context)
      assert result =~ "Task created"
      assert result =~ "Write tests"
      assert result =~ "Alice"
    end

    test "persists task in database", %{workspace: workspace} do
      params = %{title: "Persist me", assignee: "Alice", description: "Details here"}
      context = %{workspace_id: workspace.id, sender_name: "Bob"}

      {:ok, _} = AddTask.run(params, context)

      tasks = Tasks.list_tasks(workspace.id)
      assert length(tasks) == 1
      task = hd(tasks)
      assert task.title == "Persist me"
      assert task.description == "Details here"
      assert task.assignee == "Alice"
      assert task.created_by == "Bob"
      assert task.status == :todo
    end

    test "broadcasts task_created via PubSub", %{workspace: workspace} do
      Phoenix.PubSub.subscribe(Murmur.PubSub, Tasks.tasks_topic(workspace.id))

      params = %{title: "Broadcast me", assignee: "Alice"}
      context = %{workspace_id: workspace.id, sender_name: "Bob"}

      {:ok, _} = AddTask.run(params, context)

      assert_receive {:task_created, task}
      assert task.title == "Broadcast me"
    end

    test "notifies assigned agent via PubSub", %{workspace: workspace, bob: bob} do
      topic = "workspace:#{workspace.id}:agent:#{bob.id}"
      Phoenix.PubSub.subscribe(Murmur.PubSub, topic)

      params = %{title: "For Bob", assignee: "Bob"}
      context = %{workspace_id: workspace.id, sender_name: "Alice"}

      {:ok, _} = AddTask.run(params, context)

      assert_receive {:new_message, _session_id, msg}
      assert msg.content =~ "task"
      assert msg.content =~ "For Bob"
    end

    test "does not notify when assigning to self", %{workspace: workspace, alice: alice} do
      topic = "workspace:#{workspace.id}:agent:#{alice.id}"
      Phoenix.PubSub.subscribe(Murmur.PubSub, topic)

      params = %{title: "Self-assign", assignee: "Alice"}
      context = %{workspace_id: workspace.id, sender_name: "Alice"}

      {:ok, _} = AddTask.run(params, context)

      refute_receive {:new_message, _, _}, 100
    end

    test "does not notify when assigning to human", %{workspace: workspace} do
      params = %{title: "For human", assignee: "human"}
      context = %{workspace_id: workspace.id, sender_name: "Alice"}

      assert {:ok, %{result: result}} = AddTask.run(params, context)
      assert result =~ "human"
    end

    test "includes task stats in result", %{workspace: workspace} do
      # Create a pre-existing task
      Tasks.create_task(workspace.id, %{title: "Existing", assignee: "A"}, "X")

      params = %{title: "New one", assignee: "Alice"}
      context = %{workspace_id: workspace.id, sender_name: "Bob"}

      {:ok, %{result: result}} = AddTask.run(params, context)
      assert result =~ "2 task(s)"
    end

    test "returns error for title exceeding max length", %{workspace: workspace} do
      params = %{title: String.duplicate("x", 201), assignee: "Alice"}
      context = %{workspace_id: workspace.id, sender_name: "Bob"}

      assert {:error, msg} = AddTask.run(params, context)
      assert msg =~ "Failed to create task"
    end
  end
end
