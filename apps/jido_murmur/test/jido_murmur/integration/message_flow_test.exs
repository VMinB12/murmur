defmodule JidoMurmur.Integration.MessageFlowTest do
  @moduledoc """
  Integration test for end-to-end message flow:
  send -> Ingress -> Runner -> LLM (mock) -> streaming -> persistence

  Verifies that the full pipeline connects correctly with
  JidoMurmur config accessors.
  """
  use JidoMurmur.Case, async: false

  alias JidoMurmur.AgentHelper
  alias JidoMurmur.Ingress
  alias JidoMurmur.LLM
  alias JidoMurmur.Observability.SessionCache
  alias JidoMurmur.Observability.Store
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

    on_exit(fn ->
      LLM.Mock.clear_response()
      Application.put_env(:jido_murmur, :profiles, original_profiles)
      Application.put_env(:jido_murmur, :llm_adapter, JidoMurmur.LLM.Mock)
      Application.put_env(:jido_murmur, :skip_hibernate, true)
    end)

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
    assert {:ok, pid} = AgentHelper.start_agent(session)
    assert is_pid(pid)

    pubsub = JidoMurmur.pubsub()
    Phoenix.PubSub.subscribe(pubsub, StreamingPlugin.stream_topic(session.workspace_id, session.id))

    agent_topic = JidoMurmur.Topics.agent_messages(session.workspace_id, session.id)
    Phoenix.PubSub.subscribe(pubsub, agent_topic)

    LLM.Mock.set_response(%{content: "Integration test response"})

    assert :queued = Ingress.deliver(session, "Hello from integration test")

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

    assert :queued = Ingress.deliver(session, "Hello from integration test")

    assert_receive(
      {:mock_llm_phase, :started, %{request_id: request_id, call_id: call_id, waiter_pid: waiter_pid}},
      10_000
    )

    assert [{^request_id, turn}] = :ets.lookup(@turn_table, request_id)
    assert turn.agent_id == session.id
    assert turn.agent_name == session.display_name
    assert turn.workspace_id == session.workspace_id
    assert turn.session_id == session.id
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

  test "direct messages always group under the executing agent session", %{session: session} do
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

    assert :queued = Ingress.deliver(session, "first message", sent_at_ms: base_ms)

    assert_receive(
      {:mock_llm_phase, :started, %{request_id: first_request_id, waiter_pid: first_waiter_pid}},
      10_000
    )

    assert [{^first_request_id, first_turn}] = :ets.lookup(@turn_table, first_request_id)
    assert first_turn.session_id == session.id

    send(first_waiter_pid, {:release_mock_llm, first_pause_ref})
    assert_receive %Jido.Signal{type: "murmur.message.completed"}, 10_000

    pause_ref = make_ref()

    LLM.Mock.set_response(%{
      content: "second response",
      notify: self(),
      pause_after: :start,
      pause_ref: pause_ref
    })

    assert :queued = Ingress.deliver(session, "second message", sent_at_ms: base_ms + 604_800_000)

    assert_receive(
      {:mock_llm_phase, :started, %{request_id: request_id, waiter_pid: waiter_pid}},
      10_000
    )

    assert [{^request_id, turn}] = :ets.lookup(@turn_table, request_id)
    assert turn.session_id == session.id
    assert turn.session_id == first_turn.session_id

    send(waiter_pid, {:release_mock_llm, pause_ref})
    assert_receive %Jido.Signal{type: "murmur.message.completed"}, 10_000
  end

  test "busy follow-up input does not create a second root trace", %{session: session} do
    assert {:ok, _pid} = AgentHelper.start_agent(session)
    Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), JidoMurmur.Topics.agent_messages(session.workspace_id, session.id))

    first_pause_ref = make_ref()

    LLM.Mock.set_response(%{
      content: "first response",
      notify: self(),
      pause_after: :start,
      pause_ref: first_pause_ref
    })

    LLM.Mock.set_control_notify(self())

    assert :queued = Ingress.deliver(session, "first message")

    assert_receive(
      {:mock_llm_phase, :started, %{request_id: first_request_id, waiter_pid: first_waiter_pid}},
      10_000
    )

    assert [{^first_request_id, first_turn}] = :ets.lookup(@turn_table, first_request_id)
    assert first_turn.session_id == session.id

    assert :queued = Ingress.deliver(session, "second message")

    assert_receive {:mock_llm_control, :steer, %{content: "second message"}}, 10_000
    assert [{^first_request_id, still_active_turn}] = :ets.lookup(@turn_table, first_request_id)
    assert still_active_turn.session_id == session.id
    assert length(:ets.tab2list(@turn_table)) == 1

    send(first_waiter_pid, {:release_mock_llm, first_pause_ref})
    assert_receive %Jido.Signal{type: "murmur.message.completed"}, 10_000
  end

  test "idle programmatic delivery preserves immediate parent trace causation", %{session: session} do
    assert {:ok, _pid} = AgentHelper.start_agent(session)
    Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), JidoMurmur.Topics.agent_messages(session.workspace_id, session.id))

    pause_ref = make_ref()

    LLM.Mock.set_response(%{
      content: "programmatic response",
      notify: self(),
      pause_after: :start,
      pause_ref: pause_ref
    })

    assert :queued =
             Ingress.deliver_programmatic(session, "background update",
               via: :steering,
               sender_name: "Alice",
               sender_trace_id: "trace-parent-1"
             )

    assert_receive(
      {:mock_llm_phase, :started, %{request_id: request_id, waiter_pid: waiter_pid}},
      10_000
    )

    assert [{^request_id, turn}] = :ets.lookup(@turn_table, request_id)
    assert turn.session_id == session.id
    assert turn.triggered_by_trace_id == "trace-parent-1"

    send(waiter_pid, {:release_mock_llm, pause_ref})
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

    SessionCache.create_table()
    Store.create_tables()

    for table <- [@turn_table, @llm_span_table] do
      :ets.delete_all_objects(table)
    end
  rescue
    ArgumentError -> :ok
  end
end
