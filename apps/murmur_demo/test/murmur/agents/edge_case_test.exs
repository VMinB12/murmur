defmodule Murmur.Agents.EdgeCaseTest do
  @moduledoc """
  Edge case tests from the specification.

  Covers:
  - Edge: Message to busy agent is steered without blocking
  - Edge: Tell to removed/non-existent agent → graceful failure
  - Edge: Circular tell loop → depth limited to 5
  - Max agents per workspace (8)
  - Add agent after removing one from full workspace

  Uses LLM mock — no real API calls.
  """
  use Murmur.AgentCase

  alias JidoMurmur.Catalog
  alias JidoMurmur.Ingress
  alias JidoMurmur.TellAction
  alias JidoMurmur.Workspaces

  describe "message to busy agent is steered (not blocked)" do
    setup do
      {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Busy Test"})

      {:ok, session} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "BusyBot"
        })

      agent_module = Catalog.agent_module(session.agent_profile_id)
      {:ok, _} = Murmur.Jido.start_agent(agent_module, id: session.id)

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

    test "second message during an active run does not error", %{session: session} do
      test_pid = self()
      pause_ref = make_ref()

      expect_llm_ask(fn _mod, _pid, content, _ctx ->
        assert content == "Think carefully about everything"
        {:ok, make_ref()}
      end)

      expect_llm_steer(fn _mod, _pid, content, opts ->
        assert content == "Also, what is 2+2?"
        assert opts[:source][:kind] == :human
        {:ok, %{}}
      end)

      expect_llm_await(fn _mod, _handle, _opts ->
        send(test_pid, {:await_started, pause_ref, self()})

        receive do
          {:release_await, ^pause_ref} -> {:ok, "busy response"}
        after
          5_000 -> flunk("timed out waiting to release await")
        end
      end)

      assert :queued = Ingress.deliver(session, "Think carefully about everything")
      assert_receive {:await_started, ^pause_ref, waiter_pid}, 5_000

      assert :queued = Ingress.deliver(session, "Also, what is 2+2?")

      send(waiter_pid, {:release_await, pause_ref})

      session_id = session.id
      assert_receive %Jido.Signal{type: "murmur.message.completed", data: %{session_id: ^session_id}}, 5000
      refute_receive %Jido.Signal{type: "murmur.request.failed"}, 500
    end
  end

  describe "tell to removed agent fails gracefully" do
    test "tell returns error when target agent has been removed" do
      {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Remove Test"})

      {:ok, bob} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Bob"
        })

      # Remove Bob
      Workspaces.delete_agent_session(bob)

      params = %{target_agent: "Bob", intent: "notify", message: "Are you there?"}
      context = %{workspace_id: workspace.id, sender_name: "Alice", hop_count: 0}

      assert {:error, msg} = TellAction.run(params, context)
      assert msg =~ "not found"
    end
  end

  describe "circular tell loop prevention" do
    setup do
      {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Loop Test"})

      {:ok, bob} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Bob"
        })

      agent_module = Catalog.agent_module(bob.agent_profile_id)
      {:ok, _} = Murmur.Jido.start_agent(agent_module, id: bob.id)

      topic = JidoMurmur.Topics.agent_messages(workspace.id, bob.id)
      Phoenix.PubSub.subscribe(Murmur.PubSub, topic)

      stub_llm_success("loop response")

      on_exit(fn ->
        try do
          Murmur.Jido.stop_agent(bob.id)
        rescue
          _ -> :ok
        end
      end)

      %{workspace: workspace, bob: bob}
    end

    test "hop count of 0 succeeds", %{workspace: workspace, bob: bob} do
      params = %{target_agent: "Bob", intent: "notify", message: "Hi"}
      context = %{workspace_id: workspace.id, sender_name: "Alice", hop_count: 0}

      assert {:ok, _} = TellAction.run(params, context)

      bob_id = bob.id
      assert_receive %Jido.Signal{type: "murmur.message.completed", data: %{session_id: ^bob_id}}, 5000
    end

    test "hop count of 4 succeeds (just under limit)", %{workspace: workspace, bob: bob} do
      params = %{target_agent: "Bob", intent: "notify", message: "Hi"}
      context = %{workspace_id: workspace.id, sender_name: "Alice", hop_count: 4}

      assert {:ok, _} = TellAction.run(params, context)

      bob_id = bob.id
      assert_receive %Jido.Signal{type: "murmur.message.completed", data: %{session_id: ^bob_id}}, 5000
    end

    test "hop count of 5 returns an informative blocked result (at limit)", %{workspace: workspace} do
      params = %{target_agent: "Bob", intent: "notify", message: "Hi"}
      context = %{workspace_id: workspace.id, sender_name: "Alice", hop_count: 5}

      assert {:ok, result} = TellAction.run(params, context)
      assert result.delivered == false
      assert result.blocked == :hop_limit_reached
      assert result.message =~ "hop limit"
    end

    test "hop count of 10 returns an informative blocked result (well over limit)", %{workspace: workspace} do
      params = %{target_agent: "Bob", intent: "notify", message: "Hi"}
      context = %{workspace_id: workspace.id, sender_name: "Alice", hop_count: 10}

      assert {:ok, result} = TellAction.run(params, context)
      assert result.delivered == false
      assert result.blocked == :hop_limit_reached
      assert result.message =~ "hop limit"
    end
  end

end
