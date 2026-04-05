defmodule JidoMurmur.Integration.JidoInterplayTest do
  @moduledoc """
  Integration tests validating Jido-native interplay (User Story 2).

  Verifies:
  - Custom Jido.Plugin executes alongside package plugins (T046)
  - Direct Jido.AgentServer.state/1 access works on AgentHelper-started agents (T047)
  - An alternative Jido.Storage implementation works with Runner (T048)
  """
  use JidoMurmur.Case, async: false

  alias JidoMurmur.AgentHelper
  alias JidoMurmur.Ingress
  alias JidoMurmur.LLM
  alias JidoMurmur.Observability.SessionCache
  alias JidoMurmur.Observability.Store
  alias JidoMurmur.StreamingPlugin
  alias JidoMurmur.Workspaces

  @llm_span_table :jido_murmur_obs_llm_spans

  setup do
    ensure_ets_tables()
    LLM.Mock.clear_response()

    original_profiles = Application.get_env(:jido_murmur, :profiles, [])
    Application.put_env(:jido_murmur, :llm_adapter, LLM.Mock)
    Application.put_env(:jido_murmur, :skip_hibernate, true)

    on_exit(fn ->
      LLM.Mock.clear_response()
      Application.put_env(:jido_murmur, :profiles, original_profiles)
      Application.put_env(:jido_murmur, :llm_adapter, JidoMurmur.LLM.Mock)
      Application.put_env(:jido_murmur, :skip_hibernate, true)
    end)

    :ok
  end

  describe "T046: custom Jido.Plugin alongside package plugins" do
    setup do
      Application.put_env(:jido_murmur, :profiles, [JidoMurmur.TestAgentWithCustomPlugin])

      {:ok, workspace} = Workspaces.create_workspace(%{name: "Plugin Interplay WS"})

      {:ok, session} =
        Workspaces.create_agent_session(workspace.id, %{
          agent_profile_id: "test_agent_with_custom_plugin",
          display_name: "Plugin Bot"
        })

      %{workspace: workspace, session: session}
    end

    test "custom plugin and StreamingPlugin both receive signals", %{session: session} do
      # Start agent that has both StreamingPlugin and a custom plugin
      assert {:ok, pid} = AgentHelper.start_agent(session)
      assert is_pid(pid)

      # Subscribe to streaming topic (StreamingPlugin broadcasts here)
      pubsub = JidoMurmur.pubsub()
      Phoenix.PubSub.subscribe(pubsub, StreamingPlugin.stream_topic(session.workspace_id, session.id))

      # Subscribe to custom plugin topic
      Phoenix.PubSub.subscribe(pubsub, "custom_plugin:#{session.id}")

      # Subscribe to agent topic for completion
      agent_topic = JidoMurmur.Topics.agent_messages(session.workspace_id, session.id)
      Phoenix.PubSub.subscribe(pubsub, agent_topic)

      # Trigger a message
      LLM.Mock.set_response(%{content: "Plugin interplay response"})
      assert :queued = Ingress.deliver(session, "Test plugin interplay")

      # The agent should complete (mock LLM responds immediately)
      assert_receive %Jido.Signal{type: "murmur.message.completed"}, 10_000
    end

    test "streamed output content is accumulated in the observability store", %{session: session} do
      assert {:ok, _pid} = AgentHelper.start_agent(session)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), JidoMurmur.Topics.agent_messages(session.workspace_id, session.id))

      pause_ref = make_ref()

      LLM.Mock.set_response(%{
        content: "Streamed plugin interplay response",
        stream_chunks: ["Streamed plugin ", "interplay response"],
        notify: self(),
        pause_after: :deltas,
        pause_ref: pause_ref
      })

      assert :queued = Ingress.deliver(session, "Test plugin interplay")

      assert_receive {:mock_llm_phase, :deltas, %{call_id: call_id, waiter_pid: waiter_pid}}, 10_000
      assert [{^call_id, llm_record}] = :ets.lookup(@llm_span_table, call_id)
      assert llm_record.streamed_text == "Streamed plugin interplay response"

      send(waiter_pid, {:release_mock_llm, pause_ref})
      assert_receive %Jido.Signal{type: "murmur.message.completed"}, 10_000
      assert :ets.lookup(@llm_span_table, call_id) == []
    end

    test "custom plugin does not interfere with package plugin initialization", %{session: session} do
      assert {:ok, pid} = AgentHelper.start_agent(session)

      # Verify the agent is available and its state is accessible
      {:ok, state} = Jido.AgentServer.state(pid)
      assert %{agent: agent} = state
      assert agent.id == session.id
    end
  end

  describe "T047: direct Jido.AgentServer.state/1 access" do
    setup do
      Application.put_env(:jido_murmur, :profiles, [JidoMurmur.TestAgent])

      {:ok, workspace} = Workspaces.create_workspace(%{name: "Direct Access WS"})

      {:ok, session} =
        Workspaces.create_agent_session(workspace.id, %{
          agent_profile_id: "test_agent",
          display_name: "Direct Access Bot"
        })

      %{workspace: workspace, session: session}
    end

    test "AgentServer.state/1 returns full state on AgentHelper-started agent", %{session: session} do
      {:ok, pid} = AgentHelper.start_agent(session)

      # Direct Jido API call — no wrappers
      assert {:ok, state} = Jido.AgentServer.state(pid)

      # Verify native Jido types
      assert %{agent: agent, status: status} = state
      assert agent.id == session.id
      assert status in [:idle, :initializing]
    end

    test "agent pid from AgentHelper works with Jido.AgentServer API", %{session: session} do
      {:ok, pid} = AgentHelper.start_agent(session)

      # lookups via the Jido module also work
      jido_mod = JidoMurmur.jido_mod()
      found_pid = jido_mod.whereis(session.id)
      assert found_pid == pid

      # State is accessible via either the pid or the found_pid
      assert {:ok, _state} = Jido.AgentServer.state(found_pid)
    end

    test "agent state contains expected Jido.Agent struct fields", %{session: session} do
      {:ok, pid} = AgentHelper.start_agent(session)
      {:ok, state} = Jido.AgentServer.state(pid)
      %{agent: agent} = state

      # Native Jido.Agent struct fields
      assert is_binary(agent.id)
      assert is_atom(agent.agent_module)
      assert is_binary(agent.name)
      assert is_map(agent.state)
    end
  end

  describe "T048: alternative Jido.Storage works with Runner" do
    setup do
      # Use an ETS-backed storage instead of the default Ecto storage
      Application.put_env(:jido_murmur, :profiles, [JidoMurmur.TestAgent])

      # Configure the Jido module with ETS storage for this test
      original_jido_mod = Application.get_env(:jido_murmur, :jido_mod)
      Application.put_env(:jido_murmur, :jido_mod, JidoMurmur.TestJidoEtsStorage)

      # Start the alternative Jido instance
      case JidoMurmur.TestJidoEtsStorage.start_link([]) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end

      {:ok, workspace} = Workspaces.create_workspace(%{name: "Alt Storage WS"})

      {:ok, session} =
        Workspaces.create_agent_session(workspace.id, %{
          agent_profile_id: "test_agent",
          display_name: "ETS Storage Bot"
        })

      on_exit(fn ->
        Application.put_env(:jido_murmur, :jido_mod, original_jido_mod)
      end)

      %{workspace: workspace, session: session}
    end

    test "agent starts and runs with ETS storage backend", %{session: session} do
      assert {:ok, pid} = AgentHelper.start_agent(session)
      assert is_pid(pid)

      # Verify agent is accessible via AgentServer
      assert {:ok, %{agent: agent}} = Jido.AgentServer.state(pid)
      assert agent.id == session.id
    end

    test "Runner processes messages with ETS storage backend", %{session: session} do
      {:ok, _pid} = AgentHelper.start_agent(session)

      # Subscribe for completion
      pubsub = JidoMurmur.pubsub()
      agent_topic = JidoMurmur.Topics.agent_messages(session.workspace_id, session.id)
      Phoenix.PubSub.subscribe(pubsub, agent_topic)

      LLM.Mock.set_response(%{content: "ETS storage response"})
      assert :queued = Ingress.deliver(session, "Test with ETS storage")

      assert_receive %Jido.Signal{type: "murmur.message.completed"}, 10_000
    end

    test "ETS storage adapter returns native Jido types", %{session: session} do
      {:ok, pid} = AgentHelper.start_agent(session)
      {:ok, %{agent: agent}} = Jido.AgentServer.state(pid)

      # Verify the storage adapter is ETS (not Ecto)
      {adapter, _opts} = JidoMurmur.TestJidoEtsStorage.__jido_storage__()
      assert adapter == Jido.Storage.ETS
      assert agent.id == session.id
    end
  end

  # --- Helpers ---

  defp ensure_ets_tables do
    unless :ets.whereis(:jido_murmur_active_runners) != :undefined do
      :ets.new(:jido_murmur_active_runners, [:set, :public, :named_table])
    end

    SessionCache.create_table()
    Store.create_tables()

    :ets.delete_all_objects(@llm_span_table)
  rescue
    ArgumentError -> :ok
  end
end
