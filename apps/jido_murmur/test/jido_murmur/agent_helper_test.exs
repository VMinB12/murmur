defmodule JidoMurmur.AgentHelperTest do
  use JidoMurmur.Case, async: false

  alias JidoMurmur.AgentHelper
  alias JidoMurmur.Workspaces

  setup do
    ensure_ets_tables()

    original_profiles = Application.get_env(:jido_murmur, :profiles, [])
    Application.put_env(:jido_murmur, :profiles, [JidoMurmur.TestAgent])

    on_exit(fn ->
      Application.put_env(:jido_murmur, :profiles, original_profiles)
    end)

    {:ok, workspace} = Workspaces.create_workspace(%{name: "Helper Test"})

    {:ok, session} =
      Workspaces.create_agent_session(workspace.id, %{
        agent_profile_id: "test_agent",
        display_name: "Helper Bot"
      })

    %{workspace: workspace, session: session}
  end

  describe "start_agent/1" do
    test "starts an agent process for a session", %{session: session} do
      assert {:ok, pid} = AgentHelper.start_agent(session)
      assert is_pid(pid)
    end

    test "returns existing pid if already started", %{session: session} do
      {:ok, pid1} = AgentHelper.start_agent(session)
      {:ok, pid2} = AgentHelper.start_agent(session)
      assert pid1 == pid2
    end
  end

  describe "load_messages/1" do
    test "returns empty list for fresh agent", %{session: session} do
      messages = AgentHelper.load_messages(session)
      assert messages == []
    end
  end

  describe "load_artifacts/1" do
    test "returns empty map for fresh agent", %{session: session} do
      artifacts = AgentHelper.load_artifacts(session)
      assert artifacts == %{}
    end
  end

  describe "subscribe/1" do
    test "subscribes to agent topics without error", %{session: session} do
      assert :ok = AgentHelper.subscribe(session)
    end
  end

  describe "subscribe_workspace/1" do
    test "subscribes to workspace topic", %{workspace: workspace} do
      assert :ok = AgentHelper.subscribe_workspace(workspace.id)
    end
  end

  describe "cleanup_workspace_storage/1" do
    test "completes without error", %{workspace: workspace} do
      assert :ok = AgentHelper.cleanup_workspace_storage(workspace.id)
    end
  end

  defp ensure_ets_tables do
    unless :ets.whereis(:jido_murmur_active_runners) != :undefined do
      :ets.new(:jido_murmur_active_runners, [:set, :public, :named_table])
    end

    unless :ets.whereis(:jido_murmur_pending_messages) != :undefined do
      :ets.new(:jido_murmur_pending_messages, [:named_table, :public, :duplicate_bag])
    end
  rescue
    ArgumentError -> :ok
  end
end
