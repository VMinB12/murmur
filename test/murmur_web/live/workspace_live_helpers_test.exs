defmodule MurmurWeb.WorkspaceLiveHelpersTest do
  @moduledoc """
  Tests for WorkspaceLive internal helpers: thread projection and hibernate.
  Validates that AgentServer.State is correctly unwrapped to extract the Agent.
  """
  use Murmur.DataCase

  alias Murmur.Workspaces

  setup do
    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Test Workspace"})

    {:ok, session} =
      Workspaces.create_agent_session(workspace.id, %{
        "agent_profile_id" => "general_agent",
        "display_name" => "Helper"
      })

    # Start the agent so we can get its state
    alias Murmur.Agents.Catalog
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

      # project_thread should work with the Agent, not the server state
      messages = project_thread(agent)
      assert is_list(messages)
    end

    test "returns messages after a conversation turn", %{pid: pid, agent_module: agent_module} do
      {:ok, req} = agent_module.ask(pid, "hello")
      {:ok, _response} = agent_module.await(req, timeout: 30_000)

      {:ok, server_state} = Jido.AgentServer.state(pid)
      agent = server_state.agent

      thread = agent.state[:__thread__]
      assert thread != nil, "Thread should exist after a conversation"

      messages = project_thread(agent)
      assert messages != []

      # Should have at least a user and assistant message
      roles = Enum.map(messages, & &1.role)
      assert "user" in roles
      assert "assistant" in roles
    end
  end

  describe "hibernate_agent/1 persists agent state" do
    test "hibernate succeeds after a conversation", %{
      session: session,
      pid: pid,
      agent_module: agent_module
    } do
      {:ok, req} = agent_module.ask(pid, "hello")
      {:ok, _response} = agent_module.await(req, timeout: 30_000)

      # hibernate_agent should extract the agent from server state and persist
      result = hibernate_agent(session.id)
      assert result == :ok

      # Verify we can thaw the agent back
      {:ok, restored_agent} = Murmur.Jido.thaw(agent_module, session.id)
      assert restored_agent.id == session.id
    end
  end

  # --- Helpers under test (extracted from WorkspaceLive) ---
  # These mirror the private functions in WorkspaceLive so we can test them.

  defp project_thread(agent) do
    thread = get_in_thread(agent)

    if thread do
      thread.entries
      |> Enum.filter(&(&1.kind in [:message, :ai_message]))
      |> Enum.map(fn entry ->
        %{
          id: entry.id || Ecto.UUID.generate(),
          role: to_string(entry.payload[:role] || entry.payload["role"] || "assistant"),
          content: entry.payload[:content] || entry.payload["content"] || "",
          sender_name: entry.payload[:sender_name] || entry.payload["sender_name"]
        }
      end)
    else
      []
    end
  end

  defp get_in_thread(%{state: %{__thread__: thread}}) when not is_nil(thread), do: thread
  defp get_in_thread(_), do: nil

  defp hibernate_agent(session_id) do
    pid = Murmur.Jido.whereis(session_id)

    if pid do
      case Jido.AgentServer.state(pid) do
        {:ok, %{agent: agent}} ->
          Murmur.Jido.hibernate(agent)

        _ ->
          :ok
      end
    end
  end
end
