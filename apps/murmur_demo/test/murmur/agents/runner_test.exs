defmodule Murmur.Agents.RunnerTest do
  @moduledoc """
  Tests for the Runner module's core mechanics.

  Covers:
  - Ingress.deliver/2 return values
  - Agent-not-running handling
  - Rapid follow-up handling during an active run
  - Active runner lifecycle
  - FR-017: User message to busy agent not blocked
  - LLM ask error propagation

  Uses LLM mock — no real API calls.
  """
  use Murmur.AgentCase

  alias JidoMurmur.Catalog
  alias JidoMurmur.Ingress
  alias JidoMurmur.Ingress.Input
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

    topic = JidoMurmur.Topics.agent_messages(workspace.id, session.id)
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

  describe "Ingress.deliver/2 return values" do
    test "returns :queued when agent is running", %{session: session} do
      stub_llm_success()
      assert Ingress.deliver(session, "hello") == :queued

      # Wait for the background Runner Task to finish
      session_id = session.id
      assert_receive %Jido.Signal{type: "murmur.message.completed", data: %{session_id: ^session_id}}, 5000
    end

    test "returns :agent_not_running when agent process is dead" do
      {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Dead Agent"})

      {:ok, dead_session} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Ghost"
        })

      # Don't start the agent — should be :agent_not_running
      assert Ingress.deliver(dead_session, "hello") == :agent_not_running
    end
  end

  describe "message processing with mock LLM" do
    test "single message produces a mock completion", %{session: session} do
      stub_llm_success("Hello from mock")
      Ingress.deliver(session, "Say hi")

      session_id = session.id
      assert_receive %Jido.Signal{type: "murmur.message.completed", data: %{session_id: ^session_id, response: "Hello from mock"}}, 5000
    end

    test "active runner state clears after processing completes", %{session: session} do
      stub_llm_success("Done")
      Ingress.deliver(session, "Say hi")

      session_id = session.id
      assert_receive %Jido.Signal{type: "murmur.message.completed", data: %{session_id: ^session_id}}, 5000
      assert :ok = await_runner(session.id)
      refute Runner.active?(session.id)
    end

    test "LLM ask error broadcasts request_failed", %{session: session} do
      stub_llm_ask_error(:api_error)
      Ingress.deliver(session, "Say hi")

      session_id = session.id
      assert_receive %Jido.Signal{type: "murmur.request.failed", data: %{session_id: ^session_id, reason: :api_error}}, 5000
    end

    test "LLM await timeout broadcasts request_failed", %{session: session} do
      stub_llm_await_error(:timeout)
      Ingress.deliver(session, "Say hi")

      session_id = session.id
      assert_receive %Jido.Signal{type: "murmur.request.failed", data: %{session_id: ^session_id, reason: :timeout}}, 5000
    end
  end

  describe "rapid message handling" do
    test "multiple rapid messages are accepted without busy errors", %{session: session} do
      stub_llm_success("Combined response")

      Ingress.deliver(session, "first")
      Ingress.deliver(session, "second")
      Ingress.deliver(session, "third")

      session_id = session.id
      assert_receive %Jido.Signal{type: "murmur.message.completed", data: %{session_id: ^session_id}}, 5000
      refute_receive %Jido.Signal{type: "murmur.request.failed"}, 500
      assert :ok = await_runner(session.id)
    end

    test "ask receives the original direct message content", %{session: session} do
      expect_llm_ask(fn _mod, _pid, content, _ctx ->
        assert content == "first"
        {:ok, make_ref()}
      end)

      expect_llm_await(fn _mod, _handle, _opts ->
        {:ok, "Got it"}
      end)

      Ingress.deliver(session, "first")

      session_id = session.id
      assert_receive %Jido.Signal{type: "murmur.message.completed", data: %{session_id: ^session_id, response: "Got it"}}, 5000
    end
  end

  describe "busy follow-up routing" do
    test "inter-agent follow-ups are injected into an active run", %{session: session} do
      test_pid = self()
      pause_ref = make_ref()

      expect_llm_ask(fn _mod, _pid, content, _ctx ->
        assert content == "what messages have you received?"
        {:ok, make_ref()}
      end)

      expect_llm_inject(fn _mod, _pid, content, opts ->
        assert content == "injected context from another agent"
        assert opts[:source][:kind] == :programmatic
        assert opts[:extra_refs][:hop_count] == 0
        {:ok, %{}}
      end)

      expect_llm_await(fn _mod, _handle, _opts ->
        send(test_pid, {:await_started, pause_ref, self()})

        receive do
          {:release_await, ^pause_ref} -> {:ok, "Injected response"}
        after
          5_000 -> flunk("timed out waiting to release await")
        end
      end)

      assert :queued = Ingress.deliver(session, "what messages have you received?")
      assert_receive {:await_started, ^pause_ref, waiter_pid}, 5_000

      assert {:ok, input} =
               Input.programmatic_message(session, "injected context from another agent",
                 via: :steering,
                 sender_name: "Alice"
               )

      assert :queued = Ingress.deliver_input(session, input)

      send(waiter_pid, {:release_await, pause_ref})

      session_id = session.id
      assert_receive %Jido.Signal{type: "murmur.message.completed", data: %{session_id: ^session_id}}, 5000
    end
  end

  describe "multiple rapid messages — all completions broadcast" do
    test "3 rapid sends are serialized and produce completions", %{session: session} do
      stub_llm_success("Response")

      r1 = Ingress.deliver(session, "[alice]: add the following numbers")
      r2 = Ingress.deliver(session, "[alice]: 2")
      r3 = Ingress.deliver(session, "[alice]: 5")

      assert r1 == :queued
      assert r2 == :queued
      assert r3 == :queued

      # Collect completions
      session_id = session.id
      assert_receive %Jido.Signal{type: "murmur.message.completed", data: %{session_id: ^session_id}}, 5000

      # No failures
      refute_receive %Jido.Signal{type: "murmur.request.failed"}, 500
      assert :ok = await_runner(session.id)
    end

    test "rapid human follow-ups are steered into the active run", %{session: session} do
      test_pid = self()
      pause_ref = make_ref()

      expect_llm_ask(fn _mod, _pid, content, _ctx ->
        assert content == "say hi"
        {:ok, make_ref()}
      end)

      expect_llm_steer(fn _mod, _pid, content, opts ->
        assert content == "[alice]: what is 2+2?"
        assert opts[:source][:kind] == :human
        {:ok, %{}}
      end)

      expect_llm_await(fn _mod, _handle, _opts ->
        send(test_pid, {:await_started, pause_ref, self()})

        receive do
          {:release_await, ^pause_ref} -> {:ok, "Combined"}
        after
          5_000 -> flunk("timed out waiting to release await")
        end
      end)

      assert :queued = Ingress.deliver(session, "say hi")
      assert_receive {:await_started, ^pause_ref, waiter_pid}, 5_000
      assert :queued = Ingress.deliver(session, "[alice]: what is 2+2?")

      send(waiter_pid, {:release_await, pause_ref})

      session_id = session.id
      assert_receive %Jido.Signal{type: "murmur.message.completed", data: %{session_id: ^session_id}}, 5000
      assert :ok = await_runner(session.id)
    end
  end
end
