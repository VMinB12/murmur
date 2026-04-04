defmodule MurmurWeb.WorkspaceLiveHelpersTest do
  @moduledoc """
  Tests for WorkspaceLive internal helpers: thread projection and hibernate.
  Validates that AgentServer.State is correctly unwrapped to extract the Agent.

  Uses LLM mock — no real API calls.
  """
  use Murmur.AgentCase

  alias JidoMurmur.Catalog
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

  describe "project_thread/1 extracts thread from agent" do
    test "returns empty list when agent has no thread yet", %{pid: pid} do
      {:ok, server_state} = Jido.AgentServer.state(pid)
      agent = server_state.agent

      messages = WorkspaceState.project_thread(agent)
      assert is_list(messages)
    end

    test "returns messages from a populated thread", %{pid: pid} do
      # Inject a thread with entries directly into agent state (no LLM call needed)
      {:ok, server_state} = Jido.AgentServer.state(pid)
      agent = server_state.agent

      now = System.system_time(:millisecond)

      thread =
        [id: "test-thread"]
        |> Jido.Thread.new()
        |> Jido.Thread.append(%{
          kind: :message,
          payload: %{role: "user", content: "Hello"},
          at: now
        })
        |> Jido.Thread.append(%{
          kind: :ai_message,
          payload: %{role: "assistant", content: "Hi there!"},
          at: now + 1
        })

      agent = put_in(agent.state[:__thread__], thread)

  messages = WorkspaceState.project_thread(agent)
      assert length(messages) == 2

      roles = Enum.map(messages, & &1.role)
      assert "user" in roles
      assert "assistant" in roles
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
