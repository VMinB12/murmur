defmodule JidoTasks.Integration.MultiPackageTest do
  @moduledoc """
  Integration test verifying that tools from multiple packages (jido_murmur,
  jido_tasks, jido_arxiv) can compose together on a single agent's tool list
  without conflicts.
  """
  use JidoTasks.Case, async: true

  alias JidoArxiv.Tools.ArxivSearch
  alias JidoArxiv.Tools.DisplayPaper
  alias JidoTasks.Tasks
  alias JidoTasks.Tools.AddTask
  alias JidoTasks.Tools.ListTasks
  alias JidoTasks.Tools.UpdateTask

  setup do
    {:ok, workspace} =
      JidoTasks.repo().insert(%JidoMurmur.Workspaces.Workspace{name: "multi-pkg-test"})

    context = %{workspace_id: workspace.id, sender_name: "test-agent"}
    %{workspace_id: workspace.id, context: context}
  end

  describe "cross-package tool composition" do
    test "all tool modules are valid Jido.Actions" do
      tools = [AddTask, UpdateTask, ListTasks, ArxivSearch, DisplayPaper]

      for tool <- tools do
        Code.ensure_loaded!(tool)

        assert function_exported?(tool, :run, 2),
               "#{inspect(tool)} must export run/2"
      end
    end

    test "task tools and arxiv tools have distinct action names" do
      task_names =
        [AddTask, UpdateTask, ListTasks]
        |> Enum.map(& &1.__action_metadata__().name)

      arxiv_names =
        [ArxivSearch, DisplayPaper]
        |> Enum.map(& &1.__action_metadata__().name)

      all_names = task_names ++ arxiv_names

      assert length(all_names) == length(Enum.uniq(all_names)),
             "All tool action names must be unique: #{inspect(all_names)}"
    end

    test "task creation + listing works end to end", %{context: context} do
      # Create
      assert {:ok, %{result: create_result}} =
               AddTask.run(%{title: "Research ML", assignee: "arxiv-agent"}, context)

      assert create_result =~ "Task created"

      # List
      assert {:ok, %{result: list_result}} = ListTasks.run(%{}, context)
      assert list_result =~ "Research ML"
    end

    test "task lifecycle: create → update → list filtered", %{
      workspace_id: workspace_id,
      context: context
    } do
      {:ok, task} =
        Tasks.create_task(workspace_id, %{title: "Review paper", assignee: "human"}, "agent")

      # Update status
      assert {:ok, _} =
               UpdateTask.run(%{task_id: task.id, status: "in_progress"}, context)

      # List only in_progress
      assert {:ok, %{result: result}} = ListTasks.run(%{status: "in_progress"}, context)
      assert result =~ "Review paper"
    end

    test "DisplayPaper tool works alongside task tools", %{context: _context} do
      # DisplayPaper doesn't need DB, just verify it runs without conflict
      assert {:ok, %{result: result}, _directive} =
               DisplayPaper.run(%{arxiv_id: "2301.07041"}, %{})

      assert result =~ "Displaying PDF"
    end
  end
end
