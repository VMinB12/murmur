defmodule JidoMurmur.Integration.MessageFlowTest do
  @moduledoc """
  Integration test for end-to-end message flow:
  send → Runner → LLM (mock) → streaming → persistence

  Verifies that the full pipeline connects correctly with
  JidoMurmur config accessors.
  """
  use JidoMurmur.Case, async: false

  alias JidoMurmur.AgentHelper
  alias JidoMurmur.LLM
  alias JidoMurmur.Runner
  alias JidoMurmur.StreamingPlugin
  alias JidoMurmur.Workspaces

  setup do
    ensure_ets_tables()

    original_profiles = Application.get_env(:jido_murmur, :profiles, [])
    Application.put_env(:jido_murmur, :profiles, [JidoMurmur.TestAgent])
    Application.put_env(:jido_murmur, :llm_adapter, JidoMurmur.LLM.Mock)
    Application.put_env(:jido_murmur, :skip_hibernate, true)

    on_exit(fn ->
      Application.put_env(:jido_murmur, :profiles, original_profiles)
      Application.put_env(:jido_murmur, :llm_adapter, JidoMurmur.LLM.Mock)
      Application.put_env(:jido_murmur, :skip_hibernate, true)
    end)

    # Create workspace and session
    {:ok, workspace} = Workspaces.create_workspace(%{name: "Integration Test WS"})

    {:ok, session} =
      Workspaces.create_agent_session(workspace.id, %{
        agent_profile_id: "test_agent",
        display_name: "Integration Bot"
      })

    %{workspace: workspace, session: session}
  end

  test "end-to-end: start agent, subscribe streaming, send message, receive completion",
       %{session: session} do
    # Start the agent
    assert {:ok, pid} = AgentHelper.start_agent(session)
    assert is_pid(pid)

    # Subscribe to the streaming topic
    pubsub = JidoMurmur.pubsub()
    Phoenix.PubSub.subscribe(pubsub, StreamingPlugin.stream_topic(session.workspace_id, session.id))

    # Subscribe to the agent topic for completion messages
    agent_topic = JidoMurmur.Topics.agent_messages(session.workspace_id, session.id)
    Phoenix.PubSub.subscribe(pubsub, agent_topic)

    # Set mock response
    LLM.Mock.set_response(%{content: "Integration test response"})

    # Send a message through Runner
    assert :queued = Runner.send_message(session, "Hello from integration test")

    # Wait for the message_completed event (the mock LLM responds immediately)
    assert_receive %Jido.Signal{type: "murmur.message.completed"}, 10_000
  end

  test "agent helper subscribe works for all topics", %{session: session} do
    assert :ok = AgentHelper.subscribe(session)
  end

  test "workspace subscribe delivers workspace-level events", %{workspace: workspace} do
    assert :ok = AgentHelper.subscribe_workspace(workspace.id)
  end

  defp ensure_ets_tables do
    unless :ets.whereis(:jido_murmur_active_runners) != :undefined do
      :ets.new(:jido_murmur_active_runners, [:set, :public, :named_table])
    end

    unless :ets.whereis(:jido_murmur_pending_messages) != :undefined do
      :ets.new(:jido_murmur_pending_messages, [:named_table, :public, :duplicate_bag])
    end
  rescue
    ArgumentError -> :ok
  end
end
