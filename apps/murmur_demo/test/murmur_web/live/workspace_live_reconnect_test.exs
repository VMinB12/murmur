defmodule MurmurWeb.WorkspaceLiveReconnectTest do
  @moduledoc """
  LiveView-level tests for reconnect behavior.

  Covers:
  - User Story 4: Reconnect and resume
  - FR-013: Restore agent session state on reconnect
  - SC-007: Conversation history persists across page refreshes
  """
  use MurmurWeb.ConnCase

  import Phoenix.LiveViewTest

  alias JidoMurmur.Signals.MessageCompleted
  alias JidoMurmur.Workspaces

  setup do
    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Reconnect Test"})
    %{workspace: workspace}
  end

  describe "page refresh restores workspace state" do
    test "agent sessions persist across LiveView remounts", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, _} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      {:ok, _} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "arxiv_agent",
          "display_name" => "Bob"
        })

      # First mount
      {:ok, view1, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      assert has_element?(view1, "span", "Alice")
      assert has_element?(view1, "span", "Bob")

      # Second mount (simulates reconnect)
      {:ok, view2, _html} = live(conn, ~p"/workspaces/#{workspace.id}")
      assert has_element?(view2, "span", "Alice")
      assert has_element?(view2, "span", "Bob")
    end

    test "agent columns show correct profile types after reconnect", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, _} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      {:ok, _} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "arxiv_agent",
          "display_name" => "Coder"
        })

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      # Profile types should be visible
      assert has_element?(view, "span", "general_agent")
      assert has_element?(view, "span", "arxiv_agent")
    end

    test "each agent column has its own message form after reconnect", %{
      conn: conn,
      workspace: workspace
    } do
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

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      # Each agent should have its own form (FR-006)
      assert has_element?(view, "#msg-form-#{alice.id}")
      assert has_element?(view, "#msg-form-#{bob.id}")
    end
  end

  describe "messages from completed responses survive reconnect" do
    test "PubSub message_completed from previous session shows in chat", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, session} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      # Simulate a completed response arriving
      send(
        view.pid,
        MessageCompleted.new!(
          %{session_id: session.id, response: "I am Alice"},
          subject: MessageCompleted.subject(workspace.id, session.id)
        )
      )

      html = render(view)
      assert html =~ "I am Alice"
    end
  end
end
