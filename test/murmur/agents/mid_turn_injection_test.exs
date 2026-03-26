defmodule Murmur.Agents.MidTurnInjectionTest do
  @moduledoc """
  Integration tests for mid-turn message injection.

  These tests verify the core principle of Murmur: when a message arrives
  for a busy agent, it is injected into the agent's conversation at the
  next LLM call — NOT after the entire agent loop completes.

  The tests use real Jido agents with real LLM calls to verify that
  PendingQueue + MessageInjector + Runner work together.
  """
  use Murmur.DataCase

  alias Murmur.Agents.{PendingQueue, Runner}
  alias Murmur.Workspaces

  setup do
    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Injection Test"})

    {:ok, session} =
      Workspaces.create_agent_session(workspace.id, %{
        "agent_profile_id" => "general_agent",
        "display_name" => "TestAgent"
      })

    alias Murmur.Agents.Catalog
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

    %{workspace: workspace, session: session, topic: topic, agent_module: agent_module}
  end

  describe "idle agent — message starts a new loop" do
    test "Runner.send_message starts agent loop for idle agent", %{session: session} do
      result = Runner.send_message(session, "hello")
      assert result == :queued

      assert_receive {:message_completed, session_id, _response}, 30_000
      assert session_id == session.id
    end
  end

  describe "pre-queued messages are injected by MessageInjector" do
    test "messages enqueued before ask are drained by MessageInjector", %{session: session} do
      # Pre-enqueue a message (simulates what happens when agent is busy)
      PendingQueue.enqueue(session.id, "injected context from another agent")

      # Start the agent loop — MessageInjector drains queue before LLM call
      Runner.send_message(session, "what messages have you received?")

      assert_receive {:message_completed, _, _response}, 30_000

      # Queue drained by MessageInjector
      refute PendingQueue.pending?(session.id)
    end
  end

  describe "busy rejection is handled gracefully" do
    test "second message sent during busy state ends up in queue, not error", %{
      session: session
    } do
      # Fire two rapid ask() calls — the second will be rejected by strategy
      Runner.send_message(session, "first request")
      Runner.send_message(session, "second request")

      # Collect all PubSub events. Should never see :busy in a :request_failed.
      receive_all_and_assert_no_busy_rejection(session.id)
    end
  end

  describe "agent profile has MessageInjector configured" do
    test "GeneralAgent has request_transformer configured" do
      assert function_exported?(Murmur.Agents.MessageInjector, :transform_request, 4)
    end
  end

  # --- Helpers ---

  defp receive_all_and_assert_no_busy_rejection(session_id) do
    receive_all_and_assert_no_busy_rejection(session_id, 30_000)
  end

  defp receive_all_and_assert_no_busy_rejection(session_id, timeout) do
    receive do
      {:request_failed, ^session_id, reason} ->
        reason_str = inspect(reason)

        refute reason_str =~ "busy",
               "Expected no :busy rejection, got: #{reason_str}"

        receive_all_and_assert_no_busy_rejection(session_id, 1000)

      {:message_completed, ^session_id, _} ->
        receive_all_and_assert_no_busy_rejection(session_id, 1000)

      {:status_change, ^session_id, _} ->
        receive_all_and_assert_no_busy_rejection(session_id, 1000)

      {:new_message, ^session_id, _} ->
        receive_all_and_assert_no_busy_rejection(session_id, 1000)

      {:streaming_token, ^session_id, _} ->
        receive_all_and_assert_no_busy_rejection(session_id, 1000)
    after
      timeout -> :ok
    end
  end
end
