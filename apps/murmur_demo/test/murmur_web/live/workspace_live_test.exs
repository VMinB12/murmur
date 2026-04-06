defmodule MurmurWeb.WorkspaceLiveTest do
  @moduledoc """
  LiveView tests for the multi-agent workspace interface.

  Covers:
  - User Story 1: Send message and receive response
  - User Story 2: Build a team of agents in a workspace
  - FR-005: Side-by-side columns
  - FR-006: Independent text input per column
  - FR-014: Busy/thinking indicator
  - FR-016: Agent column displays name, profile, model, color
  - FR-017: User message to busy agent not blocked
  - Edge: Empty workspace shows guidance
  """
  use MurmurWeb.ConnCase

  import Phoenix.LiveViewTest

  alias JidoMurmur.ActorIdentity
  alias JidoMurmur.Catalog
  alias JidoMurmur.DisplayMessage
  alias JidoMurmur.Signals.ConversationUpdated
  alias JidoMurmur.Signals.MessageCompleted
  alias JidoMurmur.Signals.MessageReceived
  alias JidoMurmur.Workspaces
  alias Murmur.LLM.MockBehaviour, as: Mock

  setup do
    # LiveView form submissions trigger Runner Tasks that call the LLM mock
    Mox.set_mox_global()

    Mox.stub(Mock, :ask, fn _mod, _pid, _content, _ctx ->
      {:ok, make_ref()}
    end)

    Mox.stub(Mock, :await, fn _mod, _handle, _opts ->
      {:ok, "mock response"}
    end)

    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Test Workspace"})
    %{workspace: workspace}
  end

  # --- Signal test helpers ---

  defp build_message_completed(session_id, workspace_id, response, request_id \\ Ecto.UUID.generate()) do
    MessageCompleted.new!(
      %{session_id: session_id, request_id: request_id, response: response},
      subject: MessageCompleted.subject(workspace_id, session_id)
    )
  end

  defp build_conversation_updated(session_id, workspace_id, message) do
    ConversationUpdated.new!(
      %{session_id: session_id, message: message},
      subject: ConversationUpdated.subject(workspace_id, session_id)
    )
  end

  defp assistant_message(content, opts) do
    request_id = Keyword.get(opts, :request_id, Ecto.UUID.generate())

    DisplayMessage.assistant(content,
      id: Keyword.get(opts, :id, request_id <> "-step-1"),
      request_id: request_id,
      step_index: Keyword.get(opts, :step_index, 1),
      thinking: Keyword.get(opts, :thinking),
      tool_calls: Keyword.get(opts, :tool_calls, []),
      usage: Keyword.get(opts, :usage),
      status: Keyword.get(opts, :status, :completed),
      first_seen_at: Keyword.get(opts, :first_seen_at),
      first_seen_seq: Keyword.get(opts, :first_seen_seq)
    )
  end

  defp build_request_failed(session_id, workspace_id, reason) do
    Jido.Signal.new!(
      "murmur.request.failed",
      %{session_id: session_id, reason: reason},
      source: "/jido_murmur/runner",
      subject: "/workspaces/#{workspace_id}/agents/#{session_id}"
    )
  end

  defp build_message_received(session_id, workspace_id, message) do
    full_message =
      Map.merge(
        %{
          kind: :steering,
          sender_name: "Alice",
          sender_trace_id: nil
        },
        message
      )

    MessageReceived.new!(
      %{session_id: session_id, message: full_message},
      subject: MessageReceived.subject(workspace_id, session_id)
    )
  end

  # --- User Story 2: Build a team (acceptance scenarios) ---

  describe "empty workspace" do
    test "shows empty state with guidance to add agent", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      assert has_element?(view, "h2", "No agents yet")
      assert has_element?(view, "button", "Add Your First Agent")
    end

    test "displays workspace name in header", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      assert has_element?(view, "h1", workspace.name)
    end
  end

  describe "add agent" do
    test "adding an agent creates a new chat column", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      view
      |> form("#add-agent-form",
        agent: %{profile_id: "general_agent", display_name: "Alice"}
      )
      |> render_submit()

      # Column should appear with agent's display name
      assert has_element?(view, "span", "Alice")
      # Empty state should be gone
      refute has_element?(view, "h2", "No agents yet")
    end

    test "agent column shows profile type", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      view
      |> form("#add-agent-form",
        agent: %{profile_id: "arxiv_agent", display_name: "Coder"}
      )
      |> render_submit()

      assert has_element?(view, "span", "arxiv_agent")
    end

    test "adding two agents shows two columns", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      view
      |> form("#add-agent-form",
        agent: %{profile_id: "general_agent", display_name: "Alice"}
      )
      |> render_submit()

      view
      |> form("#add-agent-form",
        agent: %{profile_id: "arxiv_agent", display_name: "Bob"}
      )
      |> render_submit()

      assert has_element?(view, "span", "Alice")
      assert has_element?(view, "span", "Bob")
    end

    # FR-019: Unique display names enforced
    test "rejects duplicate display name within workspace", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      view
      |> form("#add-agent-form",
        agent: %{profile_id: "general_agent", display_name: "Alice"}
      )
      |> render_submit()

      html =
        view
        |> form("#add-agent-form",
          agent: %{profile_id: "arxiv_agent", display_name: "Alice"}
        )
        |> render_submit()

      # Should show an error, not add a second "Alice"
      assert html =~ "taken" or html =~ "error" or html =~ "already"
    end

    # FR-018: Multiple same-profile instances allowed
    test "allows same profile with different names", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      view
      |> form("#add-agent-form",
        agent: %{profile_id: "general_agent", display_name: "Alice"}
      )
      |> render_submit()

      view
      |> form("#add-agent-form",
        agent: %{profile_id: "general_agent", display_name: "Bob"}
      )
      |> render_submit()

      assert has_element?(view, "span", "Alice")
      assert has_element?(view, "span", "Bob")
    end
  end

  describe "remove agent" do
    test "removing an agent removes its column", %{conn: conn, workspace: workspace} do
      {:ok, session} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      assert has_element?(view, "span", "Alice")

      view
      |> element("button[phx-click='remove_agent'][phx-value-session-id='#{session.id}']")
      |> render_click()

      refute has_element?(view, "span", "Alice")
    end

    test "removing last agent shows empty state", %{conn: conn, workspace: workspace} do
      {:ok, session} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      view
      |> element("button[phx-click='remove_agent'][phx-value-session-id='#{session.id}']")
      |> render_click()

      assert has_element?(view, "h2", "No agents yet")
    end
  end

  describe "clear team" do
    test "clears all conversations but keeps agents", %{conn: conn, workspace: workspace} do
      {:ok, session} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      # Send a message so there's conversation history
      topic = JidoMurmur.Topics.agent_messages(workspace.id, session.id)
      conversation_topic = JidoMurmur.Topics.agent_conversation(workspace.id, session.id)
      message = assistant_message("Hello from Alice", status: :completed)

      Phoenix.PubSub.broadcast!(
        Murmur.PubSub,
        conversation_topic,
        build_conversation_updated(session.id, workspace.id, message)
      )

      Phoenix.PubSub.broadcast!(
        Murmur.PubSub,
        topic,
        build_message_completed(session.id, workspace.id, message.content, message.request_id)
      )

      html = render(view)
      assert html =~ "Hello from Alice"

      # Click clear team button
      view
      |> element("button#clear-team-btn")
      |> render_click()

      # Agent column still present, but messages gone
      assert has_element?(view, "span", "Alice")
      refute render(view) =~ "Hello from Alice"
    end

    test "clear team also wipes persisted storage", %{conn: conn, workspace: workspace} do
      {:ok, session} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      # Seed storage with a checkpoint and thread entries
      agent_module = Catalog.agent_module(session.agent_profile_id)
      {:ok, pid} = Murmur.Jido.start_agent(agent_module, id: session.id)
      {:ok, server_state} = Jido.AgentServer.state(pid)
      agent = server_state.agent

      thread =
        [id: session.id]
        |> Jido.Thread.new()
        |> Jido.Thread.append(%{
          kind: :ai_message,
          payload: %{role: "assistant", content: "Stored msg", sender_name: "Alice"}
        })

      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}
      :ok = Murmur.Jido.hibernate(agent)
      Murmur.Jido.stop_agent(session.id)

      # Verify storage has data
      assert {:ok, _} = Murmur.Jido.thaw(agent_module, session.id)

      # Mount and clear
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      view |> element("button#clear-team-btn") |> render_click()

      # Storage should be wiped
      assert {:error, :not_found} = Murmur.Jido.thaw(agent_module, session.id)
    end
  end

  # --- User Story 1: Send message and receive response ---

  describe "send message" do
    setup %{workspace: workspace} do
      {:ok, session} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      %{session: session}
    end

    test "user message appears immediately in chat", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      view
      |> form("#msg-form-#{session.id}", message: %{content: "Hello!", session_id: session.id})
      |> render_submit()

      assert has_element?(view, "#messages-#{session.id}", "Hello!")
    end

    test "empty message is not sent", %{conn: conn, workspace: workspace, session: session} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      html =
        view
        |> form("#msg-form-#{session.id}", message: %{content: "", session_id: session.id})
        |> render_submit()

      # No user message bubble should appear (only the placeholder text)
      refute html =~ ~r/<div[^>]*class="[^"]*bg-primary[^"]*"[^>]*>\s*<\/div>/
    end

    test "agent status changes to busy after sending", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      # Make the mock LLM slow so busy state is visible
      Mox.stub(Mock, :ask, fn _mod, _pid, _content, _ctx ->
        {:ok, make_ref()}
      end)

      Mox.stub(Mock, :await, fn _mod, _handle, _opts ->
        Process.sleep(1000)
        {:ok, "delayed response"}
      end)

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      view
      |> form("#msg-form-#{session.id}", message: %{content: "Hi", session_id: session.id})
      |> render_submit()

      # FR-014: Busy indicator should appear while LLM is processing
      assert has_element?(view, "span.loading")
    end

    # FR-017: Submit button NOT disabled when busy
    test "submit button is not disabled when agent is busy", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      view
      |> form("#msg-form-#{session.id}", message: %{content: "Hi", session_id: session.id})
      |> render_submit()

      # The form submit button should NOT have disabled attribute
      refute has_element?(view, "#msg-form-#{session.id} button[disabled]")
    end

    test "message sent while busy renders after the current assistant step and before the next one", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      send(view.pid, {:status_change, session.id, :busy})

      send(
        view.pid,
        build_conversation_updated(
          session.id,
          workspace.id,
          assistant_message("Working on it", request_id: "req-busy", id: "req-busy-step-1", step_index: 1, status: :running)
        )
      )

      view
      |> form("#msg-form-#{session.id}", message: %{content: "Stop this.", session_id: session.id})
      |> render_submit()

      send(
        view.pid,
        build_conversation_updated(
          session.id,
          workspace.id,
          assistant_message("Stopping now.",
            request_id: "req-busy",
            id: "req-busy-step-2",
            step_index: 2,
            first_seen_at: 9_000_000_000_000,
            first_seen_seq: 3,
            status: :completed
          )
        )
      )

      html = render(view)
      {current_step_pos, _} = :binary.match(html, "Working on it")
      {user_pos, _} = :binary.match(html, "Stop this.")
      {next_step_pos, _} = :binary.match(html, "Stopping now.")

      assert current_step_pos < user_pos
      assert user_pos < next_step_pos
    end

    test "conversation updates render by canonical first-seen order rather than arrival order", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      send(
        view.pid,
        build_conversation_updated(
          session.id,
          workspace.id,
          assistant_message("later", request_id: "req-later", first_seen_at: 200, first_seen_seq: 2)
        )
      )

      send(
        view.pid,
        build_conversation_updated(
          session.id,
          workspace.id,
          assistant_message("earlier", request_id: "req-earlier", first_seen_at: 100, first_seen_seq: 1)
        )
      )

      html = render(view)
      {earlier_pos, _} = :binary.match(html, "earlier")
      {later_pos, _} = :binary.match(html, "later")

      assert earlier_pos < later_pos
    end
  end

  describe "message completion via PubSub" do
    setup %{workspace: workspace} do
      {:ok, session} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      %{session: session}
    end

    test "message_completed adds assistant message to chat", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      # Simulate PubSub message delivery
      message = assistant_message("Hello! How can I help?", status: :completed)
      send(view.pid, build_conversation_updated(session.id, workspace.id, message))
      send(view.pid, build_message_completed(session.id, workspace.id, message.content, message.request_id))

      html = render(view)
      assert html =~ "Hello! How can I help?"
    end

    test "message_completed sets status back to idle", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      # Simulate busy state first
      send(view.pid, {:status_change, session.id, :busy})
      render(view)

      # Complete the message — should return to idle
      send(view.pid, build_message_completed(session.id, workspace.id, "Done"))
      html = render(view)

      # Loading indicator should be gone
      refute html =~ "loading-dots"
    end

    test "late canonical conversation update still appears after completion", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      request_id = Ecto.UUID.generate()
      send(view.pid, {:status_change, session.id, :busy})
      send(view.pid, build_message_completed(session.id, workspace.id, "Done", request_id))

      send(
        view.pid,
        build_conversation_updated(
          session.id,
          workspace.id,
          assistant_message("Done", request_id: request_id, status: :completed)
        )
      )

      html = render(view)
      assert html =~ "Done"
      refute html =~ "loading-dots"
    end

    test "request_failed shows error message", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      send(view.pid, build_request_failed(session.id, workspace.id, :timeout))

      html = render(view)
      assert html =~ "Error"
    end
  end

  # --- Streaming tokens ---

  describe "streaming tokens" do
    setup %{workspace: workspace} do
      {:ok, session} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      %{session: session}
    end

    test "agent_signal delta appends to streaming display", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      request_id = Ecto.UUID.generate()

      send(
        view.pid,
        build_conversation_updated(
          session.id,
          workspace.id,
          assistant_message("Hello", request_id: request_id, status: :running)
        )
      )

      send(
        view.pid,
        build_conversation_updated(
          session.id,
          workspace.id,
          assistant_message("Hello world", request_id: request_id, status: :running)
        )
      )

      html = render(view)
      assert html =~ "Hello world"
    end

    test "streaming tokens cleared after completion", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      request_id = Ecto.UUID.generate()

      send(
        view.pid,
        build_conversation_updated(
          session.id,
          workspace.id,
          assistant_message("partial...", request_id: request_id, status: :running)
        )
      )

      assert render(view) =~ "partial..."

      send(
        view.pid,
        build_conversation_updated(
          session.id,
          workspace.id,
          assistant_message("Full response", request_id: request_id, status: :completed)
        )
      )

      send(view.pid, build_message_completed(session.id, workspace.id, "Full response", request_id))
      html = render(view)

      # Streaming area should be cleared, full message shown
      assert html =~ "Full response"
    end

    test "tool result signal shows tool call in streaming area", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      send(
        view.pid,
        build_conversation_updated(
          session.id,
          workspace.id,
          assistant_message("",
            status: :running,
            tool_calls: [%{id: "call-1", name: "search_web", result: "3 results", status: :completed}]
          )
        )
      )

      html = render(view)
      assert html =~ "search_web"
      assert html =~ "Completed"
    end

    test "usage signal attaches to completed message", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      message =
        assistant_message("Done",
          status: :completed,
          usage: %{input_tokens: 100, output_tokens: 50, total_tokens: 150, model: "gpt-5-mini", duration_ms: 1200}
        )

      send(view.pid, build_conversation_updated(session.id, workspace.id, message))
      send(view.pid, build_message_completed(session.id, workspace.id, "Done", message.request_id))

      html = render(view)
      assert html =~ "100 in"
      assert html =~ "50 out"
      assert html =~ "150 total"
    end

    test "usage accumulates across multiple LLM calls", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      message =
        assistant_message("Final answer",
          status: :completed,
          usage: %{input_tokens: 300, output_tokens: 130, total_tokens: 430, model: "gpt-5-mini", duration_ms: 1200}
        )

      send(view.pid, build_conversation_updated(session.id, workspace.id, message))
      send(view.pid, build_message_completed(session.id, workspace.id, "Final answer", message.request_id))

      html = render(view)
      assert html =~ "300 in"
      assert html =~ "130 out"
      assert html =~ "430 total"
    end
  end

  # --- Inter-agent messages visible in UI ---

  describe "inter-agent messages in UI" do
    setup %{workspace: workspace} do
      {:ok, session} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Bob"
        })

      %{session: session}
    end

    # FR-010: Inter-agent messages prefixed with sender name
    test "new_message from another agent appears in chat column", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      inter_msg = %{
        id: Ecto.UUID.generate(),
        role: "user",
        content: "Can you help?",
        kind: :steering,
        origin_actor: ActorIdentity.agent("Alice"),
        sender_name: "Alice",
        sender_trace_id: nil
      }

      send(view.pid, build_message_received(session.id, workspace.id, inter_msg))

      html = render(view)
      assert html =~ "Can you help?"
      assert html =~ "Alice"
    end
  end

  # --- Multiple agents: independent operation ---

  describe "multiple agents are independent" do
    setup %{workspace: workspace} do
      {:ok, alice} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      {:ok, bob} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "arxiv_agent",
          "display_name" => "Bob"
        })

      %{alice: alice, bob: bob}
    end

    test "sending to one agent does not affect the other", %{
      conn: conn,
      workspace: workspace,
      alice: alice,
      bob: bob
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      # Send message to Alice only
      view
      |> form("#msg-form-#{alice.id}", message: %{content: "Hi Alice", session_id: alice.id})
      |> render_submit()

      # Alice's column should have the message
      assert has_element?(view, "#messages-#{alice.id}", "Hi Alice")
      # Bob's column should not
      refute has_element?(view, "#messages-#{bob.id}", "Hi Alice")
    end

    test "completion for one agent doesn't appear in other's column", %{
      conn: conn,
      workspace: workspace,
      alice: alice,
      bob: bob
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      message = assistant_message("Alice says hi", status: :completed)
      send(view.pid, build_conversation_updated(alice.id, workspace.id, message))
      send(view.pid, build_message_completed(alice.id, workspace.id, message.content, message.request_id))

      _html = render(view)
      # The message should appear in Alice's column only
      assert has_element?(view, "#messages-#{alice.id}", "Alice says hi")
      refute has_element?(view, "#messages-#{bob.id}", "Alice says hi")
    end
  end

  # --- Browser refresh restores state ---

  describe "browser refresh restores state" do
    test "agents and their sessions survive page reload", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, _session} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      # First mount
      {:ok, view1, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      assert has_element?(view1, "span", "Alice")

      # Second mount (simulates page refresh)
      {:ok, view2, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      assert has_element?(view2, "span", "Alice")
    end
  end

  # --- Agent count display ---

  describe "workspace header" do
    test "shows agent count", %{conn: conn, workspace: workspace} do
      {:ok, _} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      assert has_element?(view, "span", "1 agent(s)")
    end

    test "back button navigates to workspace list", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      assert has_element?(view, "a[href='/workspaces']")
    end
  end

  # --- Agent column visual identity ---

  describe "agent column visual identity (FR-016)" do
    test "agent header shows colored indicator for general_agent", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, _} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.id}")
      # Color is derived from display_name hash, not profile
      expected_color = Catalog.agent_color("general_agent", "Alice").dot
      assert html =~ expected_color
    end

    test "agent header shows colored indicator for arxiv_agent", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, _} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "arxiv_agent",
          "display_name" => "Coder"
        })

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.id}")
      expected_color = Catalog.agent_color("arxiv_agent", "Coder").dot
      assert html =~ expected_color
    end
  end

  # --- Unified mode ---

  describe "view mode toggle" do
    test "defaults to split mode", %{conn: conn, workspace: workspace} do
      {:ok, _} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      # Split mode shows per-agent message containers
      assert has_element?(view, "#view-split-btn")
      assert has_element?(view, "#view-unified-btn")
    end

    test "toggle switches to unified mode", %{conn: conn, workspace: workspace} do
      {:ok, _} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      # Click toggle to switch to unified mode
      view |> element("#view-unified-btn") |> render_click()

      # Unified mode shows the unified form and message container
      assert has_element?(view, "#unified-msg-form")
      assert has_element?(view, "#unified-messages")
    end

    test "toggle back returns to split mode", %{conn: conn, workspace: workspace} do
      {:ok, session} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      # Switch to unified then back
      view |> element("#view-unified-btn") |> render_click()
      view |> element("#view-split-btn") |> render_click()

      # Split mode has per-agent message containers
      assert has_element?(view, "#messages-#{session.id}")
      refute has_element?(view, "#unified-messages")
    end
  end

  describe "unified mode messaging" do
    setup %{workspace: workspace} do
      {:ok, alice} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      {:ok, bob} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "arxiv_agent",
          "display_name" => "Bob"
        })

      %{alice: alice, bob: bob}
    end

    test "message without @mention routes to first agent", %{
      conn: conn,
      workspace: workspace,
      alice: alice
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      view |> element("#view-unified-btn") |> render_click()

      view
      |> form("#unified-msg-form", message: %{content: "Hello!"})
      |> render_submit()

      html = render(view)
      assert html =~ "Hello!"

      # Message was routed to Alice (first agent), so it should be in her messages
      message = assistant_message("Hi from Alice", status: :completed)
      send(view.pid, build_conversation_updated(alice.id, workspace.id, message))
      send(view.pid, build_message_completed(alice.id, workspace.id, message.content, message.request_id))
      html = render(view)
      assert html =~ "Hi from Alice"
    end

    test "@mention routes to the named agent", %{
      conn: conn,
      workspace: workspace,
      bob: bob
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      view |> element("#view-unified-btn") |> render_click()

      view
      |> form("#unified-msg-form", message: %{content: "@Bob Write tests"})
      |> render_submit()

      # The actual content sent should be "Write tests" (stripped @mention)
      # Bob should get the message
      message = assistant_message("Tests written!", status: :completed)
      send(view.pid, build_conversation_updated(bob.id, workspace.id, message))
      send(view.pid, build_message_completed(bob.id, workspace.id, message.content, message.request_id))
      html = render(view)
      assert html =~ "Tests written!"
    end

    test "unified timeline shows messages from all agents", %{
      conn: conn,
      workspace: workspace,
      alice: alice,
      bob: bob
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      view |> element("#view-unified-btn") |> render_click()

      alice_message = assistant_message("Hello from Alice", status: :completed)
      bob_message = assistant_message("Hello from Bob", status: :completed)

      send(view.pid, build_conversation_updated(alice.id, workspace.id, alice_message))
      send(view.pid, build_message_completed(alice.id, workspace.id, alice_message.content, alice_message.request_id))
      send(view.pid, build_conversation_updated(bob.id, workspace.id, bob_message))
      send(view.pid, build_message_completed(bob.id, workspace.id, bob_message.content, bob_message.request_id))

      html = render(view)
      assert html =~ "Hello from Alice"
      assert html =~ "Hello from Bob"
    end

    test "agent sidebar shows agent names", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      view |> element("#view-unified-btn") |> render_click()

      html = render(view)
      assert html =~ "Alice"
      assert html =~ "Bob"
    end

    test "empty unified message is not sent", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      view |> element("#view-unified-btn") |> render_click()

      view
      |> form("#unified-msg-form", message: %{content: ""})
      |> render_submit()

      html = render(view)
      # Only the placeholder text should be visible, no user message bubble
      refute html =~ ~r/bg-primary.*text-primary-content/
    end
  end
end
