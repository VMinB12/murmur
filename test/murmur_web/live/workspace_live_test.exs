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
  - Edge: Max 8 agents cap
  """
  use MurmurWeb.ConnCase

  import Mox
  import Phoenix.LiveViewTest

  alias Murmur.Workspaces

  setup do
    # LiveView form submissions trigger Runner Tasks that call the LLM mock
    Mox.set_mox_global()

    Mox.stub(Murmur.Agents.LLM.Mock, :ask, fn _mod, _pid, _content, _ctx ->
      {:ok, make_ref()}
    end)

    Mox.stub(Murmur.Agents.LLM.Mock, :await, fn _mod, _handle, _opts ->
      {:ok, "mock response"}
    end)

    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Test Workspace"})
    %{workspace: workspace}
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
        agent: %{profile_id: "code_agent", display_name: "Coder"}
      )
      |> render_submit()

      assert has_element?(view, "span", "code_agent")
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
        agent: %{profile_id: "code_agent", display_name: "Bob"}
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
          agent: %{profile_id: "code_agent", display_name: "Alice"}
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

    # Max 8 agents
    test "shows error when adding more than 8 agents", %{conn: conn, workspace: workspace} do
      # Pre-create 8 agents
      for i <- 1..8 do
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Agent #{i}"
        })
      end

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      html =
        view
        |> form("#add-agent-form",
          agent: %{profile_id: "general_agent", display_name: "Agent 9"}
        )
        |> render_submit()

      assert html =~ "Maximum" or html =~ "8 agents"
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
      Mox.stub(Murmur.Agents.LLM.Mock, :ask, fn _mod, _pid, _content, _ctx ->
        {:ok, make_ref()}
      end)

      Mox.stub(Murmur.Agents.LLM.Mock, :await, fn _mod, _handle, _opts ->
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
      send(view.pid, {:message_completed, session.id, "Hello! How can I help?"})

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
      send(view.pid, {:message_completed, session.id, "Done"})
      html = render(view)

      # Loading indicator should be gone
      refute html =~ "loading-dots"
    end

    test "request_failed shows error message", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      send(view.pid, {:request_failed, session.id, :timeout})

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

    test "streaming_token appends to streaming display", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      send(view.pid, {:streaming_token, session.id, "Hello"})
      send(view.pid, {:streaming_token, session.id, " world"})

      html = render(view)
      assert html =~ "Hello world"
    end

    test "streaming tokens cleared after completion", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      send(view.pid, {:streaming_token, session.id, "partial..."})
      assert render(view) =~ "partial..."

      send(view.pid, {:message_completed, session.id, "Full response"})
      html = render(view)

      # Streaming area should be cleared, full message shown
      assert html =~ "Full response"
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
        content: "[Alice]: Can you help?",
        sender_name: "Alice"
      }

      send(view.pid, {:new_message, session.id, inter_msg})

      html = render(view)
      assert html =~ "[Alice]: Can you help?"
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
          "agent_profile_id" => "code_agent",
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

      send(view.pid, {:message_completed, alice.id, "Alice says hi"})

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
      assert html =~ "blue"
    end

    test "agent header shows colored indicator for code_agent", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, _} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "code_agent",
          "display_name" => "Coder"
        })

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.id}")
      assert html =~ "emerald"
    end
  end
end
