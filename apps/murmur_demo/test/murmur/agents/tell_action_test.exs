defmodule Murmur.Agents.TellActionTest do
  @moduledoc """
  Tests for the TellAction inter-agent communication tool.

  Covers:
  - FR-009: Agents MUST have "tell" capability
  - FR-010: Inter-agent messages prefixed with sender name
  - FR-011: Tell to idle agent triggers processing
  - FR-015: Loop depth limit (5 hops)
  - Edge: Tell to non-existent agent fails gracefully
  - Edge: Tell to removed agent fails gracefully

  Uses LLM mock — no real API calls.
  """
  use Murmur.AgentCase

  alias JidoMurmur.Catalog
  alias JidoMurmur.TellAction
  alias JidoMurmur.Workspaces

  setup do
    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Tell Test"})

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

    # Start Bob's agent process (just GenServer, no LLM call)
    agent_module = Catalog.agent_module(bob.agent_profile_id)
    {:ok, _pid} = Murmur.Jido.start_agent(agent_module, id: bob.id)

    topic = JidoMurmur.Topics.agent_messages(workspace.id, bob.id)
    Phoenix.PubSub.subscribe(Murmur.PubSub, topic)

    # Stub LLM so background Runner Task doesn't make real API calls
    stub_llm_success("Mock tell response")

    on_exit(fn ->
      try do
        Murmur.Jido.stop_agent(bob.id)
      rescue
        _ -> :ok
      end
    end)

    %{workspace: workspace, alice: alice, bob: bob}
  end

  describe "run/2 — successful delivery" do
    test "delivers message to target agent by display name", %{workspace: workspace, bob: bob} do
      params = %{target_agent: "Bob", message: "Hello Bob!"}
      context = %{workspace_id: workspace.id, sender_name: "Alice", hop_count: 0}

      assert {:ok, result} = TellAction.run(params, context)
      assert result.delivered == true
      assert result.target == "Bob"

      # Wait for the background Runner Task to finish
      bob_id = bob.id
      assert_receive {:message_completed, ^bob_id, _}, 5000
    end

    # FR-010: Messages prefixed with sender name
    test "message is prefixed with sender name in PubSub broadcast", %{
      workspace: workspace,
      bob: bob
    } do
      params = %{target_agent: "Bob", message: "Can you help?"}
      context = %{workspace_id: workspace.id, sender_name: "Alice", hop_count: 0}

      TellAction.run(params, context)

      bob_id = bob.id
      assert_receive {:new_message, ^bob_id, msg}, 5000
      assert msg.content =~ "[Alice]: Can you help?"

      # Wait for the background Runner Task to finish
      assert_receive {:message_completed, ^bob_id, _}, 5000
    end

    # FR-011: Tell triggers Runner which processes via LLM mock
    test "tell triggers Runner processing and produces mock completion", %{
      workspace: workspace,
      bob: bob
    } do
      params = %{target_agent: "Bob", message: "Process this"}
      context = %{workspace_id: workspace.id, sender_name: "Alice", hop_count: 0}

      {:ok, _} = TellAction.run(params, context)

      bob_id = bob.id
      assert_receive {:message_completed, ^bob_id, "Mock tell response"}, 5000
    end
  end

  describe "run/2 — target not found" do
    test "returns error for non-existent agent name", %{workspace: workspace} do
      params = %{target_agent: "Nobody", message: "Hello?"}
      context = %{workspace_id: workspace.id, sender_name: "Alice", hop_count: 0}

      assert {:error, msg} = TellAction.run(params, context)
      assert msg =~ "not found"
    end

    test "returns error for agent in different workspace" do
      {:ok, other_workspace} = Workspaces.create_workspace(%{"name" => "Other"})

      {:ok, _} =
        Workspaces.create_agent_session(other_workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Charlie"
        })

      {:ok, my_workspace} = Workspaces.create_workspace(%{"name" => "Mine"})

      params = %{target_agent: "Charlie", message: "Hello?"}
      context = %{workspace_id: my_workspace.id, sender_name: "Alice", hop_count: 0}

      assert {:error, msg} = TellAction.run(params, context)
      assert msg =~ "not found"
    end
  end

  # FR-015: Loop depth limit (5 hops)
  describe "run/2 — hop count limit" do
    test "rejects tell when hop count reaches 5", %{workspace: workspace} do
      params = %{target_agent: "Bob", message: "Loop!"}
      context = %{workspace_id: workspace.id, sender_name: "Alice", hop_count: 5}

      assert {:error, msg} = TellAction.run(params, context)
      assert msg =~ "Maximum" or msg =~ "hop depth"
    end

    test "allows tell at hop count 4 (below limit)", %{workspace: workspace, bob: bob} do
      params = %{target_agent: "Bob", message: "Still ok"}
      context = %{workspace_id: workspace.id, sender_name: "Alice", hop_count: 4}

      assert {:ok, _} = TellAction.run(params, context)

      # Wait for the background Runner Task to finish
      bob_id = bob.id
      assert_receive {:message_completed, ^bob_id, _}, 5000
    end
  end

  describe "run/2 — agent not running" do
    test "returns error when target agent process is not running", %{workspace: workspace} do
      {:ok, _charlie} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Charlie"
        })

      params = %{target_agent: "Charlie", message: "Hello?"}
      context = %{workspace_id: workspace.id, sender_name: "Alice", hop_count: 0}

      assert {:error, msg} = TellAction.run(params, context)
      assert msg =~ "Failed to deliver" or msg =~ "not running"
    end
  end
end
