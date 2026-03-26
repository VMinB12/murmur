defmodule Murmur.Agents.RunnerMultiMessageTest do
  @moduledoc """
  Tests for the Runner handling multiple rapid messages to the same agent.

  Reproduces the bug scenario: Alice sends 3 parallel tool calls to Bob.
  All messages must be processed and completions must be broadcast
  to PubSub. No completion should be silently lost.
  """
  use Murmur.DataCase

  alias Murmur.Agents.{PendingQueue, Runner}
  alias Murmur.Workspaces

  setup do
    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Multi Test"})

    {:ok, session} =
      Workspaces.create_agent_session(workspace.id, %{
        "agent_profile_id" => "general_agent",
        "display_name" => "Bob"
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

    %{workspace: workspace, session: session, topic: topic}
  end

  @moduletag timeout: 120_000

  describe "multiple rapid messages → all completions broadcast" do
    test "3 rapid sends are serialized and produce completions", %{session: session} do
      # Simulate Alice's 3 parallel tool calls to Bob.
      # All go to PendingQueue; the single drain loop combines + sends them.
      r1 = Runner.send_message(session, "[alice]: add the following numbers")
      r2 = Runner.send_message(session, "[alice]: 2")
      r3 = Runner.send_message(session, "[alice]: 5")

      # All should return :queued (enqueue-first design)
      assert r1 == :queued
      assert r2 == :queued
      assert r3 == :queued

      # Collect PubSub events for up to 90s.
      events = collect_events(session.id, 90_000)

      completions = Enum.filter(events, &match?({:message_completed, _, _}, &1))
      failures = Enum.filter(events, &match?({:request_failed, _, _}, &1))

      assert completions != [], "Expected at least one completion, got none"
      assert failures == [], "Expected no failures, got: #{inspect(failures)}"

      refute PendingQueue.pending?(session.id),
             "PendingQueue should be empty after all loops complete"
    end

    test "pre-queued message is injected into same LLM call by MessageInjector", %{
      session: session
    } do
      # Pre-queue a message, then start the agent loop.
      # MessageInjector drains queue before LLM call, so both messages
      # are processed in a SINGLE completion.
      PendingQueue.enqueue(session.id, "[alice]: what is 2+2?")

      Runner.send_message(session, "say hi")

      events = collect_events(session.id, 60_000)
      completions = Enum.filter(events, &match?({:message_completed, _, _}, &1))

      assert completions != [], "Expected at least one completion"

      # Queue should be drained by MessageInjector
      refute PendingQueue.pending?(session.id)
    end
  end

  # --- Helpers ---

  defp collect_events(session_id, timeout) do
    collect_events(session_id, timeout, [])
  end

  defp collect_events(session_id, timeout, acc) do
    receive do
      {:message_completed, ^session_id, _} = event ->
        collect_events(session_id, 2000, [event | acc])

      {:request_failed, ^session_id, _} = event ->
        collect_events(session_id, 2000, [event | acc])

      {:status_change, ^session_id, _} ->
        collect_events(session_id, timeout, acc)

      {:new_message, ^session_id, _} ->
        collect_events(session_id, timeout, acc)

      {:streaming_token, ^session_id, _} ->
        collect_events(session_id, timeout, acc)
    after
      timeout -> Enum.reverse(acc)
    end
  end
end
