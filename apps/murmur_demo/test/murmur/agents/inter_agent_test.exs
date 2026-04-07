defmodule Murmur.Agents.InterAgentTest do
  @moduledoc """
  Integration tests for inter-agent communication.

  Covers:
  - User Story 3: Agents communicate with each other
  - FR-009: Tell capability
  - FR-011: Tell to idle agent triggers immediate processing
  - FR-012: Tell to busy agent injects into the active run
  - FR-010: Inter-agent tells carry sender metadata in the hidden envelope
  - FR-008: Per-agent history persistence (each agent persists independently)

  Uses LLM mock — no real API calls.
  """
  use Murmur.AgentCase

  alias JidoMurmur.ActorIdentity
  alias JidoMurmur.Catalog
  alias JidoMurmur.HiddenContent
  alias JidoMurmur.Ingress
  alias JidoMurmur.TellAction
  alias JidoMurmur.Workspaces

  setup do
    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Inter-Agent Test"})

    {:ok, alice} =
      Workspaces.create_agent_session(workspace.id, %{
        "agent_profile_id" => "general_agent",
        "display_name" => "Alice"
      })

    {:ok, bob} =
      Workspaces.create_agent_session(workspace.id, %{
        "agent_profile_id" => "general_agent",
        "display_name" => "Bob"
      })

    alice_module = Catalog.agent_module(alice.agent_profile_id)
    bob_module = Catalog.agent_module(bob.agent_profile_id)

    {:ok, _} = Murmur.Jido.start_agent(alice_module, id: alice.id)
    {:ok, _} = Murmur.Jido.start_agent(bob_module, id: bob.id)

    alice_topic = JidoMurmur.Topics.agent_messages(workspace.id, alice.id)
    bob_topic = JidoMurmur.Topics.agent_messages(workspace.id, bob.id)
    Phoenix.PubSub.subscribe(Murmur.PubSub, alice_topic)
    Phoenix.PubSub.subscribe(Murmur.PubSub, bob_topic)

    # Stub LLM for all agent interactions
    stub_llm_success("Mock agent response")

    on_exit(fn ->
      for id <- [alice.id, bob.id] do
        try do
          Murmur.Jido.stop_agent(id)
        rescue
          _ -> :ok
        end
      end
    end)

    %{
      workspace: workspace,
      alice: alice,
      bob: bob,
      alice_topic: alice_topic,
      bob_topic: bob_topic
    }
  end

  describe "idle agent receives tell and responds" do
    test "sending message to idle Bob triggers processing and produces completion", %{
      workspace: workspace,
      bob: bob
    } do
      expect_llm_ask(fn _mod, _pid, content, ctx ->
        assert content ==
                 HiddenContent.wrap_markdown("What is 2+2?", sender: "Alice", intent: "request")

        assert ctx[:tool_context][:hop_count] == 1
        assert %ActorIdentity{kind: :agent, name: "Bob", id: current_actor_id} = ctx[:tool_context][:current_actor]
        assert current_actor_id == bob.id
        assert %ActorIdentity{kind: :agent, name: "Alice"} = ctx[:tool_context][:origin_actor]
        assert ctx[:extra_refs][:hop_count] == 1
        {:ok, make_ref()}
      end)

      expect_llm_await(fn _mod, _handle, _opts ->
        {:ok, "Mock agent response"}
      end)

      params = %{target_agent: "Bob", intent: "request", message: "What is 2+2?"}
      context = %{workspace_id: workspace.id, sender_name: "Alice", hop_count: 0}

      assert {:ok, _} = TellAction.run(params, context)

      bob_id = bob.id
      assert_receive %Jido.Signal{type: "murmur.message.received", data: %{session_id: ^bob_id, message: msg}}, 5000
      assert msg.kind == :tell
      assert msg.content == HiddenContent.wrap_markdown("What is 2+2?", sender: "Alice", intent: "request")
      assert msg.hop_count == 1
      assert_receive %Jido.Signal{type: "murmur.message.completed", data: %{session_id: ^bob_id, response: "Mock agent response"}}, 5000
    end
  end

  describe "busy agent receives injected tell" do
    test "tell to a busy agent is injected into the active run", %{workspace: workspace, bob: bob} do
      test_pid = self()
      pause_ref = make_ref()

      expect_llm_ask(fn _mod, _pid, content, _ctx ->
        assert content == "Think about the meaning of life"
        {:ok, make_ref()}
      end)

      expect_llm_inject(fn _mod, _pid, content, opts ->
        assert content ==
                 HiddenContent.wrap_markdown("Also, what is 3+3?", sender: "Alice", intent: "request")

        assert opts[:source][:kind] == :programmatic
        assert opts[:extra_refs][:hop_count] == 1
        {:ok, %{}}
      end)

      expect_llm_await(fn _mod, _handle, _opts ->
        send(test_pid, {:await_started, pause_ref, self()})

        receive do
          {:release_await, ^pause_ref} -> {:ok, "Mock agent response"}
        after
          5_000 -> flunk("timed out waiting to release await")
        end
      end)

      bob_id = bob.id

      assert :queued = Ingress.deliver(bob, "Think about the meaning of life")
      assert_receive %Jido.Signal{type: "murmur.message.received", data: %{session_id: ^bob_id, message: initial_msg}}, 5000
      assert initial_msg.content == "Think about the meaning of life"
      assert_receive {:await_started, ^pause_ref, waiter_pid}, 5_000

      params = %{target_agent: "Bob", intent: "request", message: "Also, what is 3+3?"}
      context = %{workspace_id: workspace.id, sender_name: "Alice", hop_count: 0}

      assert {:ok, _} = TellAction.run(params, context)
      assert_receive %Jido.Signal{type: "murmur.message.received", data: %{session_id: ^bob_id, message: msg}}, 5000
      assert msg.kind == :tell
      assert msg.content == HiddenContent.wrap_markdown("Also, what is 3+3?", sender: "Alice", intent: "request")
      assert msg.hop_count == 1

      send(waiter_pid, {:release_await, pause_ref})

      assert_receive %Jido.Signal{type: "murmur.message.completed", data: %{session_id: ^bob_id}}, 5000
      refute_receive %Jido.Signal{type: "murmur.request.failed"}, 500
    end
  end

  describe "per-agent completions are independent (FR-008)" do
    test "each agent receives its own completion separately", %{alice: alice, bob: bob} do
      Ingress.deliver(alice, "Say hello")
      Ingress.deliver(bob, "Say goodbye")

      alice_id = alice.id
      bob_id = bob.id

      # Both should receive completions independently
      assert_receive %Jido.Signal{type: "murmur.message.completed", data: %{session_id: ^alice_id}}, 5000
      assert_receive %Jido.Signal{type: "murmur.message.completed", data: %{session_id: ^bob_id}}, 5000
    end
  end

  describe "inter-agent message via TellAction appears in PubSub" do
    test "tell message to Bob broadcasts message_received with the hidden tell envelope", %{
      workspace: workspace,
      bob: bob
    } do
      params = %{target_agent: "Bob", intent: "request", message: "Can you help me?"}
      context = %{workspace_id: workspace.id, sender_name: "Alice", hop_count: 0}

      {:ok, _} = TellAction.run(params, context)

      bob_id = bob.id
      assert_receive %Jido.Signal{type: "murmur.message.received", data: %{session_id: ^bob_id, message: msg}}, 5000
      assert msg.kind == :tell
      assert msg.content == HiddenContent.wrap_markdown("Can you help me?", sender: "Alice", intent: "request")
      assert msg.hop_count == 1

      assert_receive %Jido.Signal{type: "murmur.message.completed", data: %{session_id: ^bob_id}}, 5000
    end
  end

  describe "no busy rejections with ingress coordination" do
    test "rapid sends never produce busy errors", %{bob: bob} do
      Ingress.deliver(bob, "first message")
      Ingress.deliver(bob, "second message")
      Ingress.deliver(bob, "third message")

      bob_id = bob.id

      assert_receive %Jido.Signal{type: "murmur.message.completed", data: %{session_id: ^bob_id}}, 5000

      refute_receive %Jido.Signal{type: "murmur.request.failed"}, 500
      assert :ok = await_runner(bob.id)
    end
  end
end
