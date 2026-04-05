defmodule JidoMurmur.Ingress.CoordinatorTest do
  use JidoMurmur.Case, async: false

  alias JidoMurmur.AgentHelper
  alias JidoMurmur.Ingress
  alias JidoMurmur.Ingress.Input
  alias JidoMurmur.LLM
  alias JidoMurmur.Workspaces

  setup do
    original_profiles = Application.get_env(:jido_murmur, :profiles, [])
    Application.put_env(:jido_murmur, :profiles, [JidoMurmur.TestAgent])
    Application.put_env(:jido_murmur, :llm_adapter, JidoMurmur.LLM.Mock)
    Application.put_env(:jido_murmur, :skip_hibernate, true)

    LLM.Mock.clear_response()
    LLM.Mock.clear_control_notify()

    on_exit(fn ->
      LLM.Mock.clear_response()
      LLM.Mock.clear_control_notify()
      Application.put_env(:jido_murmur, :profiles, original_profiles)
      Application.put_env(:jido_murmur, :llm_adapter, JidoMurmur.LLM.Mock)
      Application.put_env(:jido_murmur, :skip_hibernate, true)
    end)

    {:ok, workspace} = Workspaces.create_workspace(%{name: "Ingress Test Workspace"})

    {:ok, session} =
      Workspaces.create_agent_session(workspace.id, %{
        agent_profile_id: "test_agent",
        display_name: "Ingress Bot"
      })

    assert {:ok, _pid} = AgentHelper.start_agent(session)

    Phoenix.PubSub.subscribe(
      JidoMurmur.pubsub(),
      JidoMurmur.Topics.agent_messages(session.workspace_id, session.id)
    )

    %{session: session}
  end

  test "deliver starts an ask when the agent is idle", %{session: session} do
    LLM.Mock.set_response(%{content: "idle response", notify: self()})

    assert :queued = Ingress.deliver(session, "hello from ingress")

    assert_receive {:mock_llm_phase, :started, %{request_id: request_id}}, 10_000
    assert is_binary(request_id)
    assert_receive %Jido.Signal{type: "murmur.message.completed"}, 10_000
  end

  test "deliver uses steer for human follow-up while a run is active", %{session: session} do
    pause_ref = make_ref()

    LLM.Mock.set_response(%{
      content: "slow response",
      notify: self(),
      pause_after: :start,
      pause_ref: pause_ref
    })

    LLM.Mock.set_control_notify(self())

    assert :queued = Ingress.deliver(session, "first message")

    assert_receive {:mock_llm_phase, :started, %{waiter_pid: waiter_pid}}, 10_000

    assert :queued = Ingress.deliver(session, "follow up question")

    assert_receive {:mock_llm_control, :steer, %{content: "follow up question", opts: opts}}, 10_000
    assert is_binary(opts[:expected_request_id])

    send(waiter_pid, {:release_mock_llm, pause_ref})
    assert_receive %Jido.Signal{type: "murmur.message.completed"}, 10_000
  end

  test "deliver uses inject for programmatic follow-up while a run is active", %{session: session} do
    pause_ref = make_ref()

    LLM.Mock.set_response(%{
      content: "slow response",
      notify: self(),
      pause_after: :start,
      pause_ref: pause_ref
    })

    LLM.Mock.set_control_notify(self())

    assert :queued = Ingress.deliver(session, "first message")

    assert_receive {:mock_llm_phase, :started, %{waiter_pid: waiter_pid}}, 10_000

    assert :queued =
             Ingress.deliver(session, "background update",
               source: %{kind: :programmatic, via: :test},
               refs: %{interaction_id: Ecto.UUID.generate()}
             )

    assert_receive {:mock_llm_control, :inject, %{content: "background update", opts: opts}},
                   10_000

    assert is_binary(opts[:expected_request_id])

    send(waiter_pid, {:release_mock_llm, pause_ref})
    assert_receive %Jido.Signal{type: "murmur.message.completed"}, 10_000
  end

  test "deliver_input rejects invalid canonical input", %{session: session} do
    invalid_input = %Input{content: "hello", source: %{kind: :human, via: :test}, refs: %{workspace_id: session.workspace_id}}

    assert {:error, {:invalid_input, :missing_interaction_id}} =
             Ingress.deliver_input(session, invalid_input)
  end
end
