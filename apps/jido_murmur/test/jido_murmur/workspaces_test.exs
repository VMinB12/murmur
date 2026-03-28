defmodule JidoMurmur.WorkspacesTest do
  use JidoMurmur.Case, async: true

  alias JidoMurmur.Workspaces

  describe "create_workspace/1" do
    test "creates a workspace with valid attrs" do
      assert {:ok, workspace} = Workspaces.create_workspace(%{name: "Test WS"})
      assert workspace.name == "Test WS"
      assert workspace.id
    end

    test "returns error for missing name" do
      assert {:error, changeset} = Workspaces.create_workspace(%{})
      assert errors_on(changeset)[:name]
    end
  end

  describe "get_workspace!/2" do
    test "returns workspace by id" do
      {:ok, ws} = Workspaces.create_workspace(%{name: "Find Me"})
      found = Workspaces.get_workspace!(ws.id)
      assert found.name == "Find Me"
    end

    test "raises for unknown id" do
      assert_raise Ecto.NoResultsError, fn ->
        Workspaces.get_workspace!(Ecto.UUID.generate())
      end
    end
  end

  describe "list_workspaces/0" do
    test "returns all workspaces ordered by inserted_at desc" do
      {:ok, _ws1} = Workspaces.create_workspace(%{name: "First"})
      {:ok, _ws2} = Workspaces.create_workspace(%{name: "Second"})

      workspaces = Workspaces.list_workspaces()
      assert length(workspaces) >= 2
    end
  end

  describe "agent sessions" do
    setup do
      {:ok, workspace} = Workspaces.create_workspace(%{name: "Agent Test WS"})
      %{workspace: workspace}
    end

    test "create_agent_session/2 creates a session", %{workspace: ws} do
      assert {:ok, session} =
               Workspaces.create_agent_session(ws.id, %{
                 agent_profile_id: "general",
                 display_name: "General Agent"
               })

      assert session.workspace_id == ws.id
      assert session.display_name == "General Agent"
    end

    test "list_agent_sessions/1 returns sessions for workspace", %{workspace: ws} do
      Workspaces.create_agent_session(ws.id, %{
        agent_profile_id: "general",
        display_name: "Alpha"
      })

      sessions = Workspaces.list_agent_sessions(ws.id)
      assert length(sessions) == 1
      assert hd(sessions).display_name == "Alpha"
    end

    test "get_agent_session!/1 returns session by id", %{workspace: ws} do
      {:ok, session} =
        Workspaces.create_agent_session(ws.id, %{
          agent_profile_id: "general",
          display_name: "Finder"
        })

      found = Workspaces.get_agent_session!(session.id)
      assert found.display_name == "Finder"
    end

    test "find_agent_session_by_name/2 finds by name", %{workspace: ws} do
      Workspaces.create_agent_session(ws.id, %{
        agent_profile_id: "general",
        display_name: "UniqueBot"
      })

      found = Workspaces.find_agent_session_by_name(ws.id, "UniqueBot")
      assert found.display_name == "UniqueBot"
    end

    test "find_agent_session_by_name/2 returns nil for unknown name", %{workspace: ws} do
      assert is_nil(Workspaces.find_agent_session_by_name(ws.id, "Ghost"))
    end

    test "delete_agent_session/1 removes the session", %{workspace: ws} do
      {:ok, session} =
        Workspaces.create_agent_session(ws.id, %{
          agent_profile_id: "general",
          display_name: "Deletable"
        })

      assert {:ok, _} = Workspaces.delete_agent_session(session)
      assert_raise Ecto.NoResultsError, fn -> Workspaces.get_agent_session!(session.id) end
    end
  end

  # --- Helpers ---

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
