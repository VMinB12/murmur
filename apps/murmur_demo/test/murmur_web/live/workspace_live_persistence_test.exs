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

  alias Jido.Signal.ID, as: SignalID
  alias JidoMurmur.Catalog
  alias JidoMurmur.ConversationReadModel
  alias JidoMurmur.DisplayMessage
  alias JidoMurmur.Workspaces

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

    test "stale empty projector cache is refreshed from persisted storage on mount", %{
      conn: conn,
      workspace: workspace,
      session: session,
      pid: pid
    } do
      user_message_id = SignalID.generate_sequential(1_700_000_000_000, 4)

      {:ok, server_state} = Jido.AgentServer.state(pid)
      agent = server_state.agent

      thread =
        [id: session.id]
        |> Jido.Thread.new()
        |> Jido.Thread.append(%{
          kind: :ai_message,
          payload: %{role: "user", content: "Persisted user message"},
          refs: %{
            message_id: user_message_id,
            message_first_seen_at: SignalID.extract_timestamp(user_message_id),
            message_first_seen_seq: SignalID.sequence_number(user_message_id)
          }
        })
        |> Jido.Thread.append(%{
          kind: :ai_message,
          payload: %{role: "assistant", content: "Persisted assistant reply", request_id: "req-persisted"},
          refs: %{request_id: "req-persisted"}
        })

      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}
      assert :ok = Murmur.Jido.hibernate(agent)

      ref = Process.monitor(pid)
      Murmur.Jido.stop_agent(session.id)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 5_000
      assert_eventually(fn -> Murmur.Jido.whereis(session.id) == nil end)

      :ets.insert(
        :jido_murmur_conversation_snapshots,
        {session.id, JidoMurmur.ConversationReadModel.new(session.id)}
      )

      on_exit(fn -> JidoMurmur.ConversationProjector.clear(session.id) end)

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      assert has_element?(view, "#messages-#{session.id}", "Persisted user message")
      assert has_element?(view, "#messages-#{session.id}", "Persisted assistant reply")

      html = render(view)
      assert html =~ "Persisted user message"
      assert html =~ "Persisted assistant reply"

      {user_position, _} = :binary.match(html, "Persisted user message")
      {assistant_position, _} = :binary.match(html, "Persisted assistant reply")

      assert user_position < assistant_position
    end

    test "stale non-empty projector cache is refreshed from persisted storage on mount", %{
      conn: conn,
      workspace: workspace,
      session: session,
      pid: pid
    } do
      user_message_id = SignalID.generate_sequential(1_700_000_000_000, 8)

      {:ok, server_state} = Jido.AgentServer.state(pid)
      agent = server_state.agent

      thread =
        [id: session.id]
        |> Jido.Thread.new()
        |> Jido.Thread.append(%{
          kind: :ai_message,
          payload: %{role: "user", content: "Fresh persisted user"},
          refs: %{
            message_id: user_message_id,
            message_first_seen_at: SignalID.extract_timestamp(user_message_id),
            message_first_seen_seq: SignalID.sequence_number(user_message_id)
          }
        })
        |> Jido.Thread.append(%{
          kind: :ai_message,
          payload: %{role: "assistant", content: "Fresh persisted assistant", request_id: "req-fresh"},
          refs: %{request_id: "req-fresh"}
        })

      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}
      assert :ok = Murmur.Jido.hibernate(agent)

      ref = Process.monitor(pid)
      Murmur.Jido.stop_agent(session.id)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 5_000
      assert_eventually(fn -> Murmur.Jido.whereis(session.id) == nil end)

      stale_message =
        DisplayMessage.assistant("Older cached reply",
          id: "cached-step",
          request_id: "req-cached",
          step_index: 1,
          first_seen_at: 10,
          first_seen_seq: 1
        )

      :ets.insert(
        :jido_murmur_conversation_snapshots,
        {session.id, ConversationReadModel.new(session.id, [stale_message])}
      )

      on_exit(fn -> JidoMurmur.ConversationProjector.clear(session.id) end)

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      assert has_element?(view, "#messages-#{session.id}", "Fresh persisted user")
      assert has_element?(view, "#messages-#{session.id}", "Fresh persisted assistant")
      refute render(view) =~ "Older cached reply"
    end
  end
end
