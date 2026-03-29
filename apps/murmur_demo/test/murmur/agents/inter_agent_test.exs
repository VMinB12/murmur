defmodule Murmur.Agents.InterAgentTest do
  @moduledoc """
  Integration tests for inter-agent communication.

  Covers:
  - User Story 3: Agents communicate with each other
  - FR-009: Tell capability
  - FR-011: Tell to idle agent triggers immediate processing
  - FR-012: Tell to busy agent queues and injects
  - FR-010: Inter-agent messages prefixed with sender name
  - FR-008: Per-agent history persistence (each agent persists independently)

  Uses LLM mock — no real API calls.
  """
  use Murmur.AgentCase

  alias JidoMurmur.Catalog
  alias JidoMurmur.PendingQueue
  alias JidoMurmur.Runner
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

    alice_topic = "workspace:#{workspace.id}:agent:#{alice.id}"
    bob_topic = "workspace:#{workspace.id}:agent:#{bob.id}"
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
    # FR-011: Tell to idle agent triggers immediate processing
    test "sending message to idle Bob triggers processing and produces completion", %{
      bob: bob
    } do
      Runner.send_message(bob, "[Alice]: What is 2+2?")

      bob_id = bob.id
      assert_receive {:message_completed, ^bob_id, "Mock agent response"}, 5000
    end
  end

  describe "busy agent receives queued message" do
    # FR-012: Tell to busy agent queues and injects
    test "message to busy agent is queued and eventually processed", %{bob: bob} do
      # Send first message to start processing
      Runner.send_message(bob, "Think about the meaning of life")

      # Immediately send another message (Bob's loop is running)
      Runner.send_message(bob, "[Alice]: Also, what is 3+3?")

      bob_id = bob.id
      # Should receive at least one completion
      assert_receive {:message_completed, ^bob_id, _}, 5000

      # All messages should be processed
      Process.sleep(200)
      refute PendingQueue.pending?(bob.id)
    end
  end

  describe "per-agent completions are independent (FR-008)" do
    test "each agent receives its own completion separately", %{alice: alice, bob: bob} do
      Runner.send_message(alice, "Say hello")
      Runner.send_message(bob, "Say goodbye")

      alice_id = alice.id
      bob_id = bob.id

      # Both should receive completions independently
      assert_receive {:message_completed, ^alice_id, _}, 5000
      assert_receive {:message_completed, ^bob_id, _}, 5000
    end
  end

  describe "inter-agent message via TellAction appears in PubSub" do
    # FR-010: Messages prefixed with sender name
    test "tell message to Bob broadcasts :new_message with sender prefix", %{
      workspace: workspace,
      bob: bob
    } do
      params = %{target_agent: "Bob", message: "Can you help me?"}
      context = %{workspace_id: workspace.id, sender_name: "Alice", hop_count: 0}

      {:ok, _} = TellAction.run(params, context)

      bob_id = bob.id
      assert_receive {:new_message, ^bob_id, msg}, 5000
      assert msg.content =~ "[Alice]"

      # Wait for the background Runner Task to finish
      assert_receive {:message_completed, ^bob_id, _}, 5000
    end
  end

  describe "no busy rejections with serialized Runner" do
    test "rapid sends never produce busy errors", %{bob: bob} do
      # Fire multiple rapid messages
      Runner.send_message(bob, "first message")
      Runner.send_message(bob, "second message")
      Runner.send_message(bob, "third message")

      bob_id = bob.id

      # Collect events — should never see a busy rejection
      assert_receive {:message_completed, ^bob_id, _}, 5000

      refute_receive {:request_failed, ^bob_id, {:rejected, :busy, _}}, 500
      refute PendingQueue.pending?(bob.id)
    end
  end
end
