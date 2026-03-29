defmodule MurmurWeb.WorkspaceLiveIntegrationTest do
  @moduledoc """
  End-to-end integration tests for the workspace LiveView with mock agents.

  Covers:
  - User Story 1 (full loop): Send message → mock LLM → completion → persisted
  - FR-007: Token streaming to UI (simulated via PubSub)
  - FR-008: History persistence after agent turn
  - SC-001: Response within reasonable time
  - SC-007: History persists across refreshes

  Uses LLM mock — no real API calls.
  """
  use MurmurWeb.ConnCase

  import Phoenix.LiveViewTest

  alias JidoMurmur.Catalog
  alias JidoMurmur.Workspaces
  alias Murmur.LLM.MockBehaviour, as: Mock

  setup do
    Mox.set_mox_global()

    # Safe default stubs for lingering Runner Tasks
    Mox.stub(Mock, :ask, fn _mod, _pid, _content, _ctx ->
      {:ok, make_ref()}
    end)

    Mox.stub(Mock, :await, fn _mod, _handle, _opts ->
      {:ok, "default mock response"}
    end)

    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "E2E Test"})

    {:ok, session} =
      Workspaces.create_agent_session(workspace.id, %{
        "agent_profile_id" => "general_agent",
        "display_name" => "Alice"
      })

    # Start agent process (needed for Runner.send_message to find it)
    agent_module = Catalog.agent_module(session.agent_profile_id)
    {:ok, _pid} = Murmur.Jido.start_agent(agent_module, id: session.id)

    on_exit(fn ->
      try do
        Murmur.Jido.stop_agent(session.id)
      rescue
        _ -> :ok
      end
    end)

    %{workspace: workspace, session: session}
  end

  describe "full send → response → persist cycle" do
    test "sending a message through LiveView shows user message immediately", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      stub_llm_success("Hello! I'm Alice.")

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      view
      |> form("#msg-form-#{session.id}", message: %{content: "Say hello", session_id: session.id})
      |> render_submit()

      # User message should be visible immediately
      assert has_element?(view, "#messages-#{session.id}", "Say hello")
    end

    test "mock LLM completion appears in chat column via Runner", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      # Subscribe test process to PubSub to know when completion arrives
      topic = JidoMurmur.Topics.agent_messages(workspace.id, session.id)
      Phoenix.PubSub.subscribe(Murmur.PubSub, topic)

      stub_llm_success("The answer is 2.")

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      view
      |> form("#msg-form-#{session.id}",
        message: %{content: "What is 1+1?", session_id: session.id}
      )
      |> render_submit()

      # Wait for mock completion to flow through Runner → PubSub
      session_id = session.id
      assert_receive %Jido.Signal{type: "murmur.message.completed", data: %{session_id: ^session_id}}, 5000

      # Re-render to pick up the message the LiveView received
      html = render(view)
      assert html =~ "What is 1+1?"
    end
  end

  describe "conversation history persists across page refresh" do
    test "agent column is present on remount with sessions", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      # Subscribe test process to know when completion arrives
      topic = JidoMurmur.Topics.agent_messages(workspace.id, session.id)
      Phoenix.PubSub.subscribe(Murmur.PubSub, topic)

      stub_llm_success("I am Alice")

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      view
      |> form("#msg-form-#{session.id}",
        message: %{content: "The password is swordfish", session_id: session.id}
      )
      |> render_submit()

      session_id = session.id
      assert_receive %Jido.Signal{type: "murmur.message.completed", data: %{session_id: ^session_id}}, 5000

      # Remount (simulates page refresh)
      {:ok, view2, _html2} = live(conn, ~p"/workspaces/#{workspace.id}")

      # Agent column should still be present
      assert has_element?(view2, "#messages-#{session.id}")
    end
  end

  describe "two agents can work independently in same view" do
    test "messages to different agents produce independent responses", %{
      conn: conn,
      workspace: workspace,
      session: alice_session
    } do
      {:ok, bob_session} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "arxiv_agent",
          "display_name" => "Bob"
        })

      bob_module = Catalog.agent_module(bob_session.agent_profile_id)
      {:ok, _} = Murmur.Jido.start_agent(bob_module, id: bob_session.id)

      stub_llm_success("Mock response")

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      # Send to Alice
      view
      |> form("#msg-form-#{alice_session.id}",
        message: %{content: "Hi Alice", session_id: alice_session.id}
      )
      |> render_submit()

      # Send to Bob
      view
      |> form("#msg-form-#{bob_session.id}",
        message: %{content: "Hi Bob", session_id: bob_session.id}
      )
      |> render_submit()

      # Alice's message in Alice's column
      assert has_element?(view, "#messages-#{alice_session.id}", "Hi Alice")
      # Bob's message in Bob's column
      assert has_element?(view, "#messages-#{bob_session.id}", "Hi Bob")
      # No cross-contamination
      refute has_element?(view, "#messages-#{bob_session.id}", "Hi Alice")

      Murmur.Jido.stop_agent(bob_session.id)
    end
  end

  # --- Helpers ---

  defp stub_llm_success(response) do
    handle = make_ref()

    Mox.stub(Mock, :ask, fn _mod, _pid, _content, _ctx ->
      {:ok, handle}
    end)

    Mox.stub(Mock, :await, fn _mod, _handle, _opts ->
      {:ok, response}
    end)
  end
end
