defmodule MurmurWeb.WorkspaceLiveHelpersTest do
  @moduledoc """
  Tests for workspace state helpers after the conversation projector refactor.

  Uses LLM mock — no real API calls.
  """
  use Murmur.AgentCase

  alias JidoMurmur.ActorIdentity
  alias JidoMurmur.Catalog
  alias JidoMurmur.DisplayMessage
  alias JidoMurmur.Workspaces
  alias MurmurWeb.Live.WorkspaceState

  setup do
    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Test Workspace"})

    {:ok, session} =
      Workspaces.create_agent_session(workspace.id, %{
        "agent_profile_id" => "general_agent",
        "display_name" => "Helper"
      })

    agent_module = Catalog.agent_module(session.agent_profile_id)
    {:ok, pid} = Murmur.Jido.start_agent(agent_module, id: session.id)

    on_exit(fn ->
      try do
        Murmur.Jido.stop_agent(session.id)
      rescue
        _ -> :ok
      end
    end)

    %{workspace: workspace, session: session, pid: pid, agent_module: agent_module}
  end

  describe "AgentServer.state/1 returns AgentServer.State, not Agent" do
    test "AgentServer.state returns a State struct with an :agent field", %{pid: pid} do
      {:ok, server_state} = Jido.AgentServer.state(pid)

      # The return is %Jido.AgentServer.State{}, NOT %Jido.Agent{}
      assert %Jido.AgentServer.State{} = server_state
      assert %Jido.Agent{} = server_state.agent
    end
  end

  describe "load_messages_for_session/1 uses canonical snapshots" do
    test "returns empty list when no projector snapshot exists", %{session: session} do
      messages = WorkspaceState.load_messages_for_session(session)
      assert is_list(messages)
    end

    test "returns projector-backed messages when a snapshot exists", %{session: session} do
      snapshot =
        JidoMurmur.ConversationReadModel.new(session.id, [
          DisplayMessage.assistant("Hi there!", id: "req-1-step-1", request_id: "req-1", step_index: 1, status: :running)
        ])

      :ets.insert(:jido_murmur_conversation_snapshots, {session.id, snapshot})

      on_exit(fn -> JidoMurmur.ConversationProjector.clear(session.id) end)

      assert WorkspaceState.load_messages_for_session(session) == snapshot.messages
    end

    test "unified_timeline attaches canonical assistant actor identity", %{session: session} do
      messages_map = %{
        session.id => [
          DisplayMessage.assistant("Ready")
        ]
      }

      timeline = WorkspaceState.unified_timeline(messages_map, %{}, [session])

      assert [%{actor: %ActorIdentity{kind: :agent, name: "Helper", id: actor_id}}] = timeline
      assert actor_id == session.id
    end

    test "unified_timeline sorts by canonical first-seen metadata", %{session: session} do
      messages_map = %{
        session.id => [
          DisplayMessage.assistant("later", first_seen_at: 200, first_seen_seq: 2),
          DisplayMessage.user("earlier", first_seen_at: 100, first_seen_seq: 1)
        ]
      }

      timeline = WorkspaceState.unified_timeline(messages_map, %{}, [session])

      assert Enum.map(timeline, & &1.content) == ["earlier", "later"]
    end

    test "display_messages merges pending UI messages without mutating canonical history", %{session: session} do
      messages_map = %{session.id => [DisplayMessage.assistant("Ready", first_seen_at: 100, first_seen_seq: 1)]}

      pending_messages = %{
        session.id => [
          DisplayMessage.user("Queued", first_seen_at: 200, first_seen_seq: 2)
          |> Map.from_struct()
          |> Map.put(:client_ref, "client-1")
        ]
      }

      merged = WorkspaceState.display_messages(messages_map, pending_messages, session.id)

      assert Enum.map(merged, & &1.content) == ["Ready", "Queued"]
      assert messages_map[session.id] |> Enum.map(& &1.content) == ["Ready"]
    end
  end

  describe "hibernate_agent/1 persists agent state" do
    test "hibernate succeeds on a fresh agent", %{session: session, agent_module: agent_module} do
      result = WorkspaceState.hibernate_agent(session.id)
      assert result == :ok

      # Verify we can thaw the agent back
      {:ok, restored_agent} = Murmur.Jido.thaw(agent_module, session.id)
      assert restored_agent.id == session.id
    end
  end
end
