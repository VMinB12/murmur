defmodule MurmurWeb.WorkspaceLiveArtifactPersistenceTest do
  @moduledoc """
  Tests for artifact persistence across page refresh and server restart.

  Covers:
  - Artifacts stored in agent state survive hibernate/thaw
  - LiveView mount loads artifacts from running agent
  - LiveView mount loads artifacts from storage when agent is stopped
  - Artifact panel reflects persisted data after remount
  """
  use MurmurWeb.ConnCase

  import Phoenix.LiveViewTest

  alias JidoArtifacts.Envelope
  alias JidoMurmur.Catalog
  alias JidoMurmur.Workspaces

  defp envelope(data, version \\ 1) do
    Envelope.new(data, version, "agent-1", ~U[2026-01-01 00:00:00Z])
  end

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
    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Artifact Persistence Test"})

    {:ok, session} =
      Workspaces.create_agent_session(workspace.id, %{
        "agent_profile_id" => "arxiv_agent",
        "display_name" => "Scholar"
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

  @papers [
    %{
      id: "2301.00001",
      title: "Attention Is All You Need",
      abstract: "We propose...",
      url: "https://arxiv.org/abs/2301.00001",
      pdf_url: "https://arxiv.org/pdf/2301.00001"
    },
    %{
      id: "2301.00002",
      title: "BERT: Pre-training",
      abstract: "We introduce...",
      url: "https://arxiv.org/abs/2301.00002",
      pdf_url: "https://arxiv.org/pdf/2301.00002"
    }
  ]

  describe "artifacts survive agent hibernate and live view remount" do
    test "artifacts are visible after agent stop and LiveView remount", %{
      conn: conn,
      workspace: workspace,
      session: session,
      pid: pid
    } do
      # Inject artifact data directly into agent state
      {:ok, server_state} = Jido.AgentServer.state(pid)
      agent = server_state.agent
      agent = %{agent | state: Map.put(agent.state, :artifacts, %{"papers" => envelope(@papers)})}

      # Hibernate to persist the agent state (including artifacts)
      assert :ok = Murmur.Jido.hibernate(agent)

      # Stop the agent (simulates server restart)
      ref = Process.monitor(pid)
      Murmur.Jido.stop_agent(session.id)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 5000
      assert_eventually(fn -> Murmur.Jido.whereis(session.id) == nil end)

      # Mount a fresh LiveView (agent will be thawed from storage)
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      # The artifact badge should be visible in the chat column ("2 papers")
      assert has_element?(view, ~s|[phx-click="open_artifact"][phx-value-name="papers"]|)

      # Click the badge (unique text "2 papers") to open the artifact panel
      view
      |> element(~s|button[phx-click="open_artifact"]|, "2 papers")
      |> render_click()

      html = render(view)

      assert html =~ "Attention Is All You Need"
      assert html =~ "BERT: Pre-training"
    end

    test "artifacts loaded from running agent (no restart needed)", %{
      conn: conn,
      workspace: workspace,
      session: session,
      pid: pid
    } do
      # Inject artifact data directly into agent state (agent stays running)
      {:ok, server_state} = Jido.AgentServer.state(pid)
      agent = server_state.agent
      agent = %{agent | state: Map.put(agent.state, :artifacts, %{"papers" => envelope(@papers)})}

      # Update the running agent's state via hibernate + thaw cycle
      assert :ok = Murmur.Jido.hibernate(agent)

      # Stop and restart with thaw so the agent loads artifacts from checkpoint
      ref = Process.monitor(pid)
      Murmur.Jido.stop_agent(session.id)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 5000
      assert_eventually(fn -> Murmur.Jido.whereis(session.id) == nil end)

      agent_module = Catalog.agent_module(session.agent_profile_id)
      {:ok, thawed} = Murmur.Jido.thaw(agent_module, session.id)
      {:ok, _new_pid} = Murmur.Jido.start_agent(thawed, id: session.id, agent_module: agent_module)

      # Mount LiveView — should pick up artifacts from the running (restored) agent
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      # Click the badge to open the artifact detail
      view
      |> element(~s|button[phx-click="open_artifact"]|, "2 papers")
      |> render_click()

      html = render(view)

      assert html =~ "Attention Is All You Need"
      assert html =~ "BERT: Pre-training"
    end
  end

  describe "artifact state round-trip through checkpoint" do
    test "hibernate saves artifacts and thaw restores them", %{
      session: session,
      agent_module: agent_module,
      pid: pid
    } do
      # Get agent and add artifacts
      {:ok, server_state} = Jido.AgentServer.state(pid)
      agent = server_state.agent
      agent = %{agent | state: Map.put(agent.state, :artifacts, %{"papers" => envelope(@papers)})}

      # Hibernate
      assert :ok = Murmur.Jido.hibernate(agent)

      # Thaw from storage
      {:ok, restored} = Murmur.Jido.thaw(agent_module, session.id)

      # Artifacts should be present in the restored agent's state
      assert restored.state.artifacts == %{"papers" => envelope(@papers)}
    end

    test "empty artifacts survive round-trip", %{
      session: session,
      agent_module: agent_module,
      pid: pid
    } do
      {:ok, server_state} = Jido.AgentServer.state(pid)
      agent = server_state.agent

      # Explicitly set empty artifacts
      agent = %{agent | state: Map.put(agent.state, :artifacts, %{})}
      assert :ok = Murmur.Jido.hibernate(agent)

      {:ok, restored} = Murmur.Jido.thaw(agent_module, session.id)
      assert restored.state.artifacts == %{}
    end
  end
end
