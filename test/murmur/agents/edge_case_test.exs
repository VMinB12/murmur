defmodule Murmur.Agents.EdgeCaseTest do
  @moduledoc """
  Edge case tests from the specification.

  Covers:
  - Edge: Message to busy agent → injected into pending
  - Edge: Tell to removed/non-existent agent → graceful failure
  - Edge: Circular tell loop → depth limited to 5
  - Max agents per workspace (8)
  - Add agent after removing one from full workspace

  Uses LLM mock — no real API calls.
  """
  use Murmur.AgentCase

  alias Murmur.Agents.{Catalog, PendingQueue, Runner, TellAction}
  alias Murmur.Workspaces

  describe "message to busy agent is queued (not blocked)" do
    setup do
      {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Busy Test"})

      {:ok, session} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "BusyBot"
        })

      agent_module = Catalog.agent_module(session.agent_profile_id)
      {:ok, _} = Murmur.Jido.start_agent(agent_module, id: session.id)

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

    test "second message during busy does not error", %{session: session} do
      stub_llm_success("busy response")

      # Send first message (starts processing)
      assert :queued = Runner.send_message(session, "Think carefully about everything")

      # Second message while first is processing
      assert :queued = Runner.send_message(session, "Also, what is 2+2?")

      session_id = session.id

      # Should get completion(s), never busy rejections
      assert_receive {:message_completed, ^session_id, _}, 5000

      refute_receive {:request_failed, ^session_id, {:rejected, :busy, _}}, 500

      # All messages processed
      Process.sleep(200)
      refute PendingQueue.pending?(session.id)
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

      params = %{target_agent: "Bob", message: "Are you there?"}
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

      topic = "workspace:#{workspace.id}:agent:#{bob.id}"
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
      params = %{target_agent: "Bob", message: "Hi"}
      context = %{workspace_id: workspace.id, sender_name: "Alice", hop_count: 0}

      assert {:ok, _} = TellAction.run(params, context)

      # Wait for the background Runner Task to finish
      bob_id = bob.id
      assert_receive {:message_completed, ^bob_id, _}, 5000
    end

    test "hop count of 4 succeeds (just under limit)", %{workspace: workspace, bob: bob} do
      params = %{target_agent: "Bob", message: "Hi"}
      context = %{workspace_id: workspace.id, sender_name: "Alice", hop_count: 4}

      assert {:ok, _} = TellAction.run(params, context)

      # Wait for the background Runner Task to finish
      bob_id = bob.id
      assert_receive {:message_completed, ^bob_id, _}, 5000
    end

    test "hop count of 5 is rejected (at limit)", %{workspace: workspace} do
      params = %{target_agent: "Bob", message: "Hi"}
      context = %{workspace_id: workspace.id, sender_name: "Alice", hop_count: 5}

      assert {:error, msg} = TellAction.run(params, context)
      assert msg =~ "Maximum" or msg =~ "hop"
    end

    test "hop count of 10 is rejected (well over limit)", %{workspace: workspace} do
      params = %{target_agent: "Bob", message: "Hi"}
      context = %{workspace_id: workspace.id, sender_name: "Alice", hop_count: 10}

      assert {:error, msg} = TellAction.run(params, context)
      assert msg =~ "Maximum" or msg =~ "hop"
    end
  end

  describe "max agents per workspace" do
    test "cannot add 9th agent" do
      {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Max Test"})

      for i <- 1..8 do
        {:ok, _} =
          Workspaces.create_agent_session(workspace.id, %{
            "agent_profile_id" => "general_agent",
            "display_name" => "Agent #{i}"
          })
      end

      assert {:error, :max_agents_reached} =
               Workspaces.create_agent_session(workspace.id, %{
                 "agent_profile_id" => "general_agent",
                 "display_name" => "Agent 9"
               })
    end

    test "can add agent after removing one from full workspace" do
      {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Max Test 2"})

      sessions =
        for i <- 1..8 do
          {:ok, session} =
            Workspaces.create_agent_session(workspace.id, %{
              "agent_profile_id" => "general_agent",
              "display_name" => "Agent #{i}"
            })

          session
        end

      # Remove one
      Workspaces.delete_agent_session(List.first(sessions))

      # Should now be able to add
      assert {:ok, _} =
               Workspaces.create_agent_session(workspace.id, %{
                 "agent_profile_id" => "general_agent",
                 "display_name" => "Replacement"
               })
    end
  end
end
