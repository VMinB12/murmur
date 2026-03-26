defmodule MurmurWeb.WorkspaceLivePersistenceTest do
  @moduledoc """
  Tests for conversation history persistence across server restarts.

  Covers:
  - SC-007: Conversation history persists across page refreshes — no messages lost
  - FR-008: Per-agent history persistence after completed turn
  - FR-013: Restore agent session state on reconnect

  Populates agent thread directly and hibernates to storage, then verifies
  LiveView mount restores messages from storage when agent is gone.
  """
  use MurmurWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Murmur.Agents.Catalog
  alias Murmur.Workspaces

  defp assert_eventually(fun, retries \\ 50) do
    if fun.() do
      :ok
    else
      if retries > 0 do
        Process.sleep(10)
        assert_eventually(fun, retries - 1)
      else
        flunk("Condition not met after retries")
      end
    end
  end

  setup do
    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Persistence Test"})

    {:ok, session} =
      Workspaces.create_agent_session(workspace.id, %{
        "agent_profile_id" => "general_agent",
        "display_name" => "Alice"
      })

    agent_module = Catalog.agent_module(session.agent_profile_id)
    {:ok, pid} = Murmur.Jido.start_agent(agent_module, id: session.id)

    on_exit(fn ->
      try do
        Murmur.Jido.stop_agent(session.id)
      rescue
        _ -> :ok
      catch
        :exit, _ -> :ok
      end
    end)

    %{workspace: workspace, session: session, agent_module: agent_module, pid: pid}
  end

  describe "conversation history survives server restart" do
    test "messages are visible after agent stop and LiveView remount", %{
      conn: conn,
      workspace: workspace,
      session: session,
      pid: pid
    } do
      # Get the running agent and add thread entries to simulate a conversation
      {:ok, server_state} = Jido.AgentServer.state(pid)
      agent = server_state.agent

      thread =
        [id: session.id]
        |> Jido.Thread.new()
        |> Jido.Thread.append(%{
          kind: :message,
          payload: %{role: "user", content: "Hello Alice!", sender_name: "User"}
        })
        |> Jido.Thread.append(%{
          kind: :ai_message,
          payload: %{
            role: "assistant",
            content: "Persisted response from Alice",
            sender_name: "Alice"
          }
        })

      # Put thread into agent state and hibernate
      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}
      assert :ok = Murmur.Jido.hibernate(agent)

      # Stop the agent (simulates server restart — agent process is gone)
      ref = Process.monitor(pid)
      Murmur.Jido.stop_agent(session.id)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 5000

      # Registry cleanup is async — wait for it to propagate
      assert_eventually(fn -> Murmur.Jido.whereis(session.id) == nil end)

      # Mount a fresh LiveView (simulates user opening the page after restart)
      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.id}")

      # The persisted response should be visible from storage
      assert html =~ "Persisted response from Alice"
    end
  end
end
