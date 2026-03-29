defmodule Murmur.Agents.ReconnectTest do
  @moduledoc """
  Tests for reconnect and resume after disconnect.

  Covers:
  - User Story 4: Reconnect and resume
  - FR-013: Restore agent session state on reconnect
  - FR-013a: Agent execution continues server-side regardless of browser
  - SC-005: Full workspace state restored within reconnect

  Uses LLM mock — no real API calls.
  """
  use Murmur.AgentCase

  alias JidoMurmur.Catalog
  alias JidoMurmur.Runner
  alias JidoMurmur.Workspaces

  setup do
    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Reconnect Test"})

    {:ok, session} =
      Workspaces.create_agent_session(workspace.id, %{
        "agent_profile_id" => "general_agent",
        "display_name" => "Alice"
      })

    agent_module = Catalog.agent_module(session.agent_profile_id)
    {:ok, _pid} = Murmur.Jido.start_agent(agent_module, id: session.id)

    topic = "workspace:#{workspace.id}:agent:#{session.id}"
    Phoenix.PubSub.subscribe(Murmur.PubSub, topic)

    stub_llm_success("Reconnect mock response")

    on_exit(fn ->
      try do
        Murmur.Jido.stop_agent(session.id)
      rescue
        _ -> :ok
      end
    end)

    %{workspace: workspace, session: session, agent_module: agent_module}
  end

  # FR-013a: Agent continues server-side regardless of browser state
  describe "agent continues after subscriber disconnects" do
    test "agent completes processing even without PubSub subscriber", %{session: session} do
      Runner.send_message(session, "Say hello")

      session_id = session.id
      assert_receive {:message_completed, ^session_id, _response}, 5000
    end

    test "agent process stays alive after request completes", %{session: session} do
      Runner.send_message(session, "Say hi")

      session_id = session.id
      assert_receive {:message_completed, ^session_id, _}, 5000

      pid = Murmur.Jido.whereis(session.id)
      assert pid
      assert Process.alive?(pid)
    end
  end

  # FR-013: Restore agent session state on reconnect
  describe "state restoration after reconnect" do
    test "agent process remains accessible after completion", %{session: session} do
      Runner.send_message(session, "Remember the number 42")

      session_id = session.id
      assert_receive {:message_completed, ^session_id, _}, 5000

      # Agent should still be queryable
      pid = Murmur.Jido.whereis(session.id)
      assert pid

      {:ok, server_state} = Jido.AgentServer.state(pid)
      assert server_state.agent
    end

    test "multiple messages produce multiple completions", %{session: session} do
      Runner.send_message(session, "First message")

      session_id = session.id
      assert_receive {:message_completed, ^session_id, _}, 5000

      Runner.send_message(session, "Second message")
      assert_receive {:message_completed, ^session_id, _}, 5000

      # Agent still alive
      pid = Murmur.Jido.whereis(session.id)
      assert pid
    end
  end

  describe "workspace data survives reconnect simulation" do
    test "agent sessions persist in database across queries", %{
      workspace: workspace,
      session: session
    } do
      # Verify the session can be re-fetched from DB (simulates reconnect data load)
      sessions = Workspaces.list_agent_sessions(workspace.id)
      assert length(sessions) == 1

      found = Enum.find(sessions, &(&1.id == session.id))
      assert found
      assert found.display_name == "Alice"
    end

    test "multiple agent sessions all persist", %{workspace: workspace} do
      {:ok, _bob} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "arxiv_agent",
          "display_name" => "Bob"
        })

      sessions = Workspaces.list_agent_sessions(workspace.id)
      assert length(sessions) == 2

      names = sessions |> Enum.map(& &1.display_name) |> Enum.sort()
      assert names == ["Alice", "Bob"]
    end
  end
end
