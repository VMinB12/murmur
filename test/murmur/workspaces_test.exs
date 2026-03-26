defmodule Murmur.WorkspacesTest do
  @moduledoc """
  Tests for the Workspaces context module.

  Covers:
  - FR-002: Users MUST be able to create a workspace
  - FR-003: Users MUST be able to add agents with display name
  - FR-004: Users MUST be able to remove an agent
  - FR-018: Multiple same-profile instances allowed
  - FR-019: Unique display names enforced per workspace
  - Edge: Max 8 agents per workspace
  """
  use Murmur.DataCase

  alias Murmur.Workspaces

  # --- Workspace CRUD ---

  describe "create_workspace/1" do
    test "creates a workspace with valid attrs" do
      assert {:ok, workspace} = Workspaces.create_workspace(%{"name" => "My Team"})
      assert workspace.name == "My Team"
      assert workspace.id
    end

    test "rejects workspace without name" do
      assert {:error, changeset} = Workspaces.create_workspace(%{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects workspace with name exceeding 255 chars" do
      long_name = String.duplicate("a", 256)
      assert {:error, changeset} = Workspaces.create_workspace(%{"name" => long_name})
      assert %{name: [msg]} = errors_on(changeset)
      assert msg =~ "should be at most 255"
    end
  end

  describe "get_workspace!/1" do
    test "returns the workspace with given id" do
      {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Test"})
      assert Workspaces.get_workspace!(workspace.id).name == "Test"
    end

    test "raises for non-existent id" do
      assert_raise Ecto.NoResultsError, fn ->
        Workspaces.get_workspace!(Ecto.UUID.generate())
      end
    end
  end

  describe "list_workspaces/0" do
    test "returns all workspaces ordered by newest first" do
      {:ok, w1} = Workspaces.create_workspace(%{"name" => "First"})
      {:ok, w2} = Workspaces.create_workspace(%{"name" => "Second"})
      workspaces = Workspaces.list_workspaces()
      assert [w2.id, w1.id] == Enum.map(workspaces, & &1.id)
    end

    test "returns empty list when no workspaces exist" do
      assert Workspaces.list_workspaces() == []
    end
  end

  # --- Agent Session CRUD ---

  describe "create_agent_session/2" do
    setup do
      {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Test"})
      %{workspace: workspace}
    end

    test "creates an agent session with valid attrs", %{workspace: workspace} do
      assert {:ok, session} =
               Workspaces.create_agent_session(workspace.id, %{
                 "agent_profile_id" => "general_agent",
                 "display_name" => "Alice"
               })

      assert session.display_name == "Alice"
      assert session.agent_profile_id == "general_agent"
      assert session.workspace_id == workspace.id
    end

    test "rejects session without display_name", %{workspace: workspace} do
      assert {:error, changeset} =
               Workspaces.create_agent_session(workspace.id, %{
                 "agent_profile_id" => "general_agent"
               })

      assert %{display_name: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects session without agent_profile_id", %{workspace: workspace} do
      assert {:error, changeset} =
               Workspaces.create_agent_session(workspace.id, %{
                 "display_name" => "Alice"
               })

      assert %{agent_profile_id: ["can't be blank"]} = errors_on(changeset)
    end

    # FR-018: Multiple same-profile instances allowed
    test "allows same profile added multiple times with different names", %{workspace: workspace} do
      assert {:ok, _} =
               Workspaces.create_agent_session(workspace.id, %{
                 "agent_profile_id" => "general_agent",
                 "display_name" => "Alice"
               })

      assert {:ok, _} =
               Workspaces.create_agent_session(workspace.id, %{
                 "agent_profile_id" => "general_agent",
                 "display_name" => "Bob"
               })
    end

    # FR-019: Unique display names enforced per workspace
    test "rejects duplicate display name within same workspace", %{workspace: workspace} do
      assert {:ok, _} =
               Workspaces.create_agent_session(workspace.id, %{
                 "agent_profile_id" => "general_agent",
                 "display_name" => "Alice"
               })

      assert {:error, changeset} =
               Workspaces.create_agent_session(workspace.id, %{
                 "agent_profile_id" => "code_agent",
                 "display_name" => "Alice"
               })

      errors = errors_on(changeset)
      # Ecto maps composite unique constraint to first field in the index
      assert errors[:workspace_id] || errors[:display_name],
             "Expected unique constraint error on workspace_id or display_name, got: #{inspect(errors)}"
    end

    test "allows same display name in different workspaces" do
      {:ok, w1} = Workspaces.create_workspace(%{"name" => "W1"})
      {:ok, w2} = Workspaces.create_workspace(%{"name" => "W2"})

      assert {:ok, _} =
               Workspaces.create_agent_session(w1.id, %{
                 "agent_profile_id" => "general_agent",
                 "display_name" => "Alice"
               })

      assert {:ok, _} =
               Workspaces.create_agent_session(w2.id, %{
                 "agent_profile_id" => "general_agent",
                 "display_name" => "Alice"
               })
    end

    # Max 8 agents per workspace
    test "rejects when workspace has reached 8 agents", %{workspace: workspace} do
      for i <- 1..8 do
        assert {:ok, _} =
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
  end

  describe "delete_agent_session/1" do
    test "removes the session from the workspace" do
      {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Test"})

      {:ok, session} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      assert {:ok, _} = Workspaces.delete_agent_session(session)
      assert Workspaces.list_agent_sessions(workspace.id) == []
    end
  end

  describe "list_agent_sessions/1" do
    test "returns sessions ordered by insertion time" do
      {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Test"})

      {:ok, s1} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "First"
        })

      {:ok, s2} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "code_agent",
          "display_name" => "Second"
        })

      sessions = Workspaces.list_agent_sessions(workspace.id)
      assert [s1.id, s2.id] == Enum.map(sessions, & &1.id)
    end

    test "returns empty list for workspace with no sessions" do
      {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Empty"})
      assert Workspaces.list_agent_sessions(workspace.id) == []
    end
  end

  describe "find_agent_session_by_name/2" do
    test "finds session by display name within workspace" do
      {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Test"})

      {:ok, session} =
        Workspaces.create_agent_session(workspace.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      found = Workspaces.find_agent_session_by_name(workspace.id, "Alice")
      assert found.id == session.id
    end

    test "returns nil for non-existent display name" do
      {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Test"})
      assert Workspaces.find_agent_session_by_name(workspace.id, "Nobody") == nil
    end

    test "does not find sessions from other workspaces" do
      {:ok, w1} = Workspaces.create_workspace(%{"name" => "W1"})
      {:ok, w2} = Workspaces.create_workspace(%{"name" => "W2"})

      {:ok, _} =
        Workspaces.create_agent_session(w1.id, %{
          "agent_profile_id" => "general_agent",
          "display_name" => "Alice"
        })

      assert Workspaces.find_agent_session_by_name(w2.id, "Alice") == nil
    end
  end
end
