defmodule JidoMurmur.TellActionTest do
  use JidoMurmur.Case, async: false

  alias JidoMurmur.ActorIdentity
  alias JidoMurmur.TellAction
  alias JidoMurmur.Workspaces

  describe "run/2" do
    test "returns error when target agent not found" do
      {:ok, workspace} = Workspaces.create_workspace(%{name: "tell-test"})

      params = %{target_agent: "NonExistent", message: "hello"}
      context = %{workspace_id: workspace.id, current_actor: ActorIdentity.agent("sender"), hop_count: 0}

      assert {:error, msg} = TellAction.run(params, context)
      assert msg =~ "not found"
    end

    test "returns informative result when max hop depth is exceeded" do
      {:ok, workspace} = Workspaces.create_workspace(%{name: "hop-test"})

      Workspaces.create_agent_session(workspace.id, %{
        display_name: "Target",
        agent_profile_id: "general"
      })

      params = %{target_agent: "Target", message: "hello"}
      context = %{workspace_id: workspace.id, current_actor: ActorIdentity.agent("sender"), hop_count: 5}

      assert {:ok, result} = TellAction.run(params, context)
      assert result.delivered == false
      assert result.blocked == :hop_limit_reached
      assert result.hop_limit == 5
      assert result.message =~ "hop limit"
    end

    test "defaults hop_count to 0 when not present in context" do
      {:ok, workspace} = Workspaces.create_workspace(%{name: "default-hop"})

      params = %{target_agent: "Nobody", message: "hello"}
      context = %{workspace_id: workspace.id, current_actor: ActorIdentity.agent("sender")}

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
        context = %{workspace_id: workspace.id, current_actor: ActorIdentity.agent("sender"), hop_count: 0}

      assert {:error, msg} = TellAction.run(params, context)
      assert msg =~ "Failed to deliver"
    end

    test "uses configured hop limit" do
      original_limit = Application.get_env(:jido_murmur, :tell_hop_limit)
      Application.put_env(:jido_murmur, :tell_hop_limit, 2)

      on_exit(fn ->
        if is_nil(original_limit) do
          Application.delete_env(:jido_murmur, :tell_hop_limit)
        else
          Application.put_env(:jido_murmur, :tell_hop_limit, original_limit)
        end
      end)

      {:ok, workspace} = Workspaces.create_workspace(%{name: "configured-hop-limit"})

      params = %{target_agent: "Nobody", message: "hello"}
      context = %{workspace_id: workspace.id, current_actor: ActorIdentity.agent("sender"), hop_count: 2}

      assert {:ok, result} = TellAction.run(params, context)
      assert result.blocked == :hop_limit_reached
      assert result.hop_limit == 2
    end
  end
end
