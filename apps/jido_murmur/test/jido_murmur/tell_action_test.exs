defmodule JidoMurmur.TellActionTest do
  use JidoMurmur.Case, async: true

  alias JidoMurmur.TellAction
  alias JidoMurmur.Workspaces

  describe "run/2" do
    test "returns error when target agent not found" do
      {:ok, workspace} = Workspaces.create_workspace(%{name: "tell-test"})

      params = %{target_agent: "NonExistent", message: "hello"}
      context = %{workspace_id: workspace.id, sender_name: "sender", hop_count: 0}

      assert {:error, msg} = TellAction.run(params, context)
      assert msg =~ "not found"
    end

    test "returns error when max hop depth exceeded" do
      {:ok, workspace} = Workspaces.create_workspace(%{name: "hop-test"})

      Workspaces.create_agent_session(workspace.id, %{
        display_name: "Target",
        agent_profile_id: "general"
      })

      params = %{target_agent: "Target", message: "hello"}
      context = %{workspace_id: workspace.id, sender_name: "sender", hop_count: 5}

      assert {:error, msg} = TellAction.run(params, context)
      assert msg =~ "Maximum inter-agent hop depth"
    end

    test "defaults hop_count to 0 when not present in context" do
      {:ok, workspace} = Workspaces.create_workspace(%{name: "default-hop"})

      params = %{target_agent: "Nobody", message: "hello"}
      context = %{workspace_id: workspace.id, sender_name: "sender"}

      # Should fail with "not found" (not hop error), proving hop_count defaulted to 0
      assert {:error, msg} = TellAction.run(params, context)
      assert msg =~ "not found"
    end

    test "returns error when target agent exists but is not running" do
      {:ok, workspace} = Workspaces.create_workspace(%{name: "not-running"})

      {:ok, _session} =
        Workspaces.create_agent_session(workspace.id, %{
          display_name: "OfflineAgent",
          agent_profile_id: "general"
        })

      params = %{target_agent: "OfflineAgent", message: "hello"}
      context = %{workspace_id: workspace.id, sender_name: "sender", hop_count: 0}

      assert {:error, msg} = TellAction.run(params, context)
      assert msg =~ "Failed to deliver"
    end
  end
end
