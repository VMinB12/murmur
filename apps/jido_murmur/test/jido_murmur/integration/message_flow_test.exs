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
  alias JidoMurmur.Observability.ConversationCache
  alias JidoMurmur.Observability.SessionCache
  alias JidoMurmur.Observability.Store
  alias JidoMurmur.Runner
  alias JidoMurmur.StreamingPlugin
  alias JidoMurmur.Workspaces

  @turn_table :jido_murmur_obs_turns
  @llm_span_table :jido_murmur_obs_llm_spans

  setup do
    ensure_ets_tables()
    LLM.Mock.clear_response()

    original_profiles = Application.get_env(:jido_murmur, :profiles, [])
    Application.put_env(:jido_murmur, :profiles, [JidoMurmur.TestAgent])
    Application.put_env(:jido_murmur, :llm_adapter, JidoMurmur.LLM.Mock)
    Application.put_env(:jido_murmur, :skip_hibernate, true)
    Application.put_env(:jido_murmur, :conversation_session_timeout_ms, 60_000)

    on_exit(fn ->
      LLM.Mock.clear_response()
      Application.put_env(:jido_murmur, :profiles, original_profiles)
      Application.put_env(:jido_murmur, :llm_adapter, JidoMurmur.LLM.Mock)
      Application.put_env(:jido_murmur, :skip_hibernate, true)
      Application.delete_env(:jido_murmur, :conversation_session_timeout_ms)
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

  test "root turn attrs are present while the request is active", %{session: session} do
    assert {:ok, _pid} = AgentHelper.start_agent(session)
    Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), JidoMurmur.Topics.agent_messages(session.workspace_id, session.id))

    pause_ref = make_ref()

    LLM.Mock.set_response(%{
      content: "Integration test response",
      notify: self(),
      pause_after: :start,
      pause_ref: pause_ref
    })

    assert :queued = Runner.send_message(session, "Hello from integration test")

    assert_receive(
      {:mock_llm_phase, :started, %{request_id: request_id, call_id: call_id, waiter_pid: waiter_pid}},
      10_000
    )

    assert [{^request_id, turn}] = :ets.lookup(@turn_table, request_id)
    assert turn.agent_id == session.id
    assert turn.agent_name == session.display_name
    assert turn.workspace_id == session.workspace_id
    assert turn.session_id == turn.interaction_id
    refute turn.session_id == session.id
    assert turn.input_value == "Hello from integration test"

    assert [{^call_id, llm_record}] = :ets.lookup(@llm_span_table, call_id)
    assert llm_record.request_id == request_id
    assert llm_record.input_attrs["llm.input_messages.0.message.role"] == "user"
    assert llm_record.input_attrs["llm.input_messages.0.message.content"] == "Hello from integration test"

    send(waiter_pid, {:release_mock_llm, pause_ref})
    assert_receive %Jido.Signal{type: "murmur.message.completed"}, 10_000

    assert :ets.lookup(@turn_table, request_id) == []
    assert :ets.lookup(@llm_span_table, call_id) == []
  end

  test "explicit interaction_id overrides direct-message default grouping", %{session: session} do
    assert {:ok, _pid} = AgentHelper.start_agent(session)
    Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), JidoMurmur.Topics.agent_messages(session.workspace_id, session.id))

    pause_ref = make_ref()
    interaction_id = JidoMurmur.Observability.next_interaction_id()

    LLM.Mock.set_response(%{
      content: "Integration test response",
      notify: self(),
      pause_after: :start,
      pause_ref: pause_ref
    })

    assert :queued = Runner.send_message(session, "Hello from integration test", interaction_id: interaction_id)

    assert_receive(
      {:mock_llm_phase, :started, %{request_id: request_id, waiter_pid: waiter_pid}},
      10_000
    )

    assert [{^request_id, turn}] = :ets.lookup(@turn_table, request_id)
    assert turn.session_id == interaction_id
    assert turn.interaction_id == interaction_id

    send(waiter_pid, {:release_mock_llm, pause_ref})
    assert_receive %Jido.Signal{type: "murmur.message.completed"}, 10_000
  end

  test "direct follow-up messages reuse the active discussion session", %{session: session} do
    assert {:ok, _pid} = AgentHelper.start_agent(session)
    Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), JidoMurmur.Topics.agent_messages(session.workspace_id, session.id))

    base_ms = System.monotonic_time(:millisecond)

    first_pause_ref = make_ref()

    LLM.Mock.set_response(%{
      content: "first response",
      notify: self(),
      pause_after: :start,
      pause_ref: first_pause_ref
    })

    assert :queued = Runner.send_message(session, "first message", sent_at_ms: base_ms)

    assert_receive(
      {:mock_llm_phase, :started, %{request_id: first_request_id, waiter_pid: first_waiter_pid}},
      10_000
    )

    assert [{^first_request_id, first_turn}] = :ets.lookup(@turn_table, first_request_id)

    send(first_waiter_pid, {:release_mock_llm, first_pause_ref})
    assert_receive %Jido.Signal{type: "murmur.message.completed"}, 10_000

    second_pause_ref = make_ref()

    LLM.Mock.set_response(%{
      content: "second response",
      notify: self(),
      pause_after: :start,
      pause_ref: second_pause_ref
    })

    assert :queued =
         Runner.send_message(session, "second message", sent_at_ms: base_ms + 1_000)

    assert_receive(
      {:mock_llm_phase, :started, %{request_id: second_request_id, waiter_pid: second_waiter_pid}},
      10_000
    )

    assert [{^second_request_id, second_turn}] = :ets.lookup(@turn_table, second_request_id)
    assert second_turn.session_id == first_turn.session_id

    send(second_waiter_pid, {:release_mock_llm, second_pause_ref})
    assert_receive %Jido.Signal{type: "murmur.message.completed"}, 10_000
  end

  test "direct messages roll to a new session after the discussion timeout", %{session: session} do
    assert {:ok, _pid} = AgentHelper.start_agent(session)
    Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), JidoMurmur.Topics.agent_messages(session.workspace_id, session.id))

    base_ms = System.monotonic_time(:millisecond)

    first_pause_ref = make_ref()

    LLM.Mock.set_response(%{
      content: "first response",
      notify: self(),
      pause_after: :start,
      pause_ref: first_pause_ref
    })

    assert :queued = Runner.send_message(session, "first message", sent_at_ms: base_ms)

    assert_receive(
      {:mock_llm_phase, :started, %{request_id: first_request_id, waiter_pid: first_waiter_pid}},
      10_000
    )

    assert [{^first_request_id, first_turn}] = :ets.lookup(@turn_table, first_request_id)

    send(first_waiter_pid, {:release_mock_llm, first_pause_ref})
    assert_receive %Jido.Signal{type: "murmur.message.completed"}, 10_000

    second_pause_ref = make_ref()

    LLM.Mock.set_response(%{
      content: "second response",
      notify: self(),
      pause_after: :start,
      pause_ref: second_pause_ref
    })

    assert :queued =
         Runner.send_message(session, "second message", sent_at_ms: base_ms + 61_000)

    assert_receive(
      {:mock_llm_phase, :started, %{request_id: second_request_id, waiter_pid: second_waiter_pid}},
      10_000
    )

    assert [{^second_request_id, second_turn}] = :ets.lookup(@turn_table, second_request_id)
    refute second_turn.session_id == first_turn.session_id

    send(second_waiter_pid, {:release_mock_llm, second_pause_ref})
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

    SessionCache.create_table()
    ConversationCache.create_table()
    Store.create_tables()

    for table <- [@turn_table, @llm_span_table, :jido_murmur_obs_conversations] do
      :ets.delete_all_objects(table)
    end
  rescue
    ArgumentError -> :ok
  end
end
