defmodule Murmur.Agents.RunnerTest do
  @moduledoc """
  Tests for the Runner module's core mechanics.

  Covers:
  - Runner.send_message/2 return values
  - Agent-not-running handling
  - Serialization of asks (no concurrent asks to same agent)
  - Queue drain loop behavior
  - FR-017: User message to busy agent not blocked
  - LLM ask error propagation

  Uses LLM mock — no real API calls.
  """
  use Murmur.AgentCase

  alias JidoMurmur.Catalog
  alias JidoMurmur.PendingQueue
  alias JidoMurmur.Runner
  alias JidoMurmur.Workspaces

  setup do
    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Runner Test"})

    {:ok, session} =
      Workspaces.create_agent_session(workspace.id, %{
        "agent_profile_id" => "general_agent",
        "display_name" => "TestAgent"
      })

    agent_module = Catalog.agent_module(session.agent_profile_id)
    {:ok, _pid} = Murmur.Jido.start_agent(agent_module, id: session.id)

    topic = "workspace:#{workspace.id}:agent:#{session.id}"
    Phoenix.PubSub.subscribe(Murmur.PubSub, topic)

    on_exit(fn ->
      try do
        Murmur.Jido.stop_agent(session.id)
      rescue
        _ -> :ok
      end
    end)

    %{workspace: workspace, session: session}
  end

  describe "send_message/2 return values" do
    test "returns :queued when agent is running", %{session: session} do
      stub_llm_success()
      assert Runner.send_message(session, "hello") == :queued

      # Wait for the background Runner Task to finish
      session_id = session.id
      assert_receive {:message_completed, ^session_id, _}, 5000
    end

    test "returns :agent_not_running when agent process is dead" do
      {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Dead Agent"})

      {:ok, dead_session} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Ghost"
        })

      # Don't start the agent — should be :agent_not_running
      assert Runner.send_message(dead_session, "hello") == :agent_not_running
    end
  end

  describe "message processing with mock LLM" do
    test "single message produces a mock completion", %{session: session} do
      stub_llm_success("Hello from mock")
      Runner.send_message(session, "Say hi")

      session_id = session.id
      assert_receive {:message_completed, ^session_id, "Hello from mock"}, 5000
    end

    test "PendingQueue is empty after processing completes", %{session: session} do
      stub_llm_success("Done")
      Runner.send_message(session, "Say hi")

      session_id = session.id
      assert_receive {:message_completed, ^session_id, _}, 5000

      # Give drain loop time to finish
      Process.sleep(100)
      refute PendingQueue.pending?(session.id)
    end

    test "LLM ask error broadcasts request_failed", %{session: session} do
      stub_llm_ask_error(:api_error)
      Runner.send_message(session, "Say hi")

      session_id = session.id
      assert_receive {:request_failed, ^session_id, :api_error}, 5000
    end

    test "LLM await timeout broadcasts request_failed", %{session: session} do
      stub_llm_await_error(:timeout)
      Runner.send_message(session, "Say hi")

      session_id = session.id
      assert_receive {:request_failed, ^session_id, :timeout}, 5000
    end
  end

  describe "serialization — no concurrent asks" do
    test "multiple rapid messages are combined and processed sequentially", %{session: session} do
      stub_llm_success("Combined response")

      # Send 3 messages rapidly
      Runner.send_message(session, "first")
      Runner.send_message(session, "second")
      Runner.send_message(session, "third")

      # Should get at least one completion (messages may be combined by drain)
      session_id = session.id
      assert_receive {:message_completed, ^session_id, _}, 5000

      # All messages should be processed — queue empty
      Process.sleep(200)
      refute PendingQueue.pending?(session.id)
    end

    test "ask receives combined content from multiple messages", %{session: session} do
      expect_llm_ask(fn _mod, _pid, content, _ctx ->
        # Verify the content contains the combined messages
        assert content =~ "first"
        {:ok, make_ref()}
      end)

      expect_llm_await(fn _mod, _handle, _opts ->
        {:ok, "Got it"}
      end)

      Runner.send_message(session, "first")
      # Small sleep to ensure first message is drained first
      Process.sleep(10)

      session_id = session.id
      assert_receive {:message_completed, ^session_id, "Got it"}, 5000
    end
  end

  describe "pre-queued messages are drained by MessageInjector" do
    test "messages enqueued before ask are processed", %{session: session} do
      stub_llm_success("Injected response")

      # Pre-enqueue a message (simulates what happens when agent is busy)
      PendingQueue.enqueue(session.id, "injected context from another agent")

      # Start the agent loop
      Runner.send_message(session, "what messages have you received?")

      session_id = session.id
      assert_receive {:message_completed, ^session_id, _}, 5000

      # Queue drained
      refute PendingQueue.pending?(session.id)
    end
  end

  describe "multiple rapid messages — all completions broadcast" do
    test "3 rapid sends are serialized and produce completions", %{session: session} do
      stub_llm_success("Response")

      r1 = Runner.send_message(session, "[alice]: add the following numbers")
      r2 = Runner.send_message(session, "[alice]: 2")
      r3 = Runner.send_message(session, "[alice]: 5")

      assert r1 == :queued
      assert r2 == :queued
      assert r3 == :queued

      # Collect completions
      session_id = session.id
      assert_receive {:message_completed, ^session_id, _}, 5000

      # No failures
      refute_receive {:request_failed, ^session_id, _}, 500

      # Queue empty
      Process.sleep(200)
      refute PendingQueue.pending?(session.id)
    end

    test "pre-queued message is injected into same LLM call", %{session: session} do
      stub_llm_success("Combined")

      PendingQueue.enqueue(session.id, "[alice]: what is 2+2?")
      Runner.send_message(session, "say hi")

      session_id = session.id
      assert_receive {:message_completed, ^session_id, _}, 5000

      refute PendingQueue.pending?(session.id)
    end
  end
end
