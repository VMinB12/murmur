defmodule JidoMurmur.Workspaces do
  @moduledoc "Context for managing workspaces and agent sessions."

  import Ecto.Query

  alias JidoMurmur.Workspaces.AgentSession
  alias JidoMurmur.Workspaces.Workspace

  def create_workspace(attrs) do
    repo = JidoMurmur.repo()

    %Workspace{}
    |> Workspace.changeset(attrs)
    |> repo.insert()
  end

  def get_workspace!(id, scope \\ %{}) do
    repo = JidoMurmur.repo()
    workspace = repo.get!(Workspace, id)
    authorize!(:read, workspace, scope)
    workspace
  end

  def list_workspaces do
    repo = JidoMurmur.repo()
    repo.all(from w in Workspace, order_by: [desc: w.inserted_at])
  end

  def list_agent_sessions(workspace_id) do
    repo = JidoMurmur.repo()

    repo.all(
      from as in AgentSession,
        where: as.workspace_id == ^workspace_id,
        order_by: [asc: as.inserted_at]
    )
  end

  def create_agent_session(workspace_id, attrs) do
    repo = JidoMurmur.repo()

    %AgentSession{workspace_id: workspace_id}
    |> AgentSession.changeset(attrs)
    |> repo.insert()
  end

  def delete_agent_session(%AgentSession{} = session) do
    repo = JidoMurmur.repo()
    repo.delete(session)
  end

  def get_agent_session!(id) do
    repo = JidoMurmur.repo()
    repo.get!(AgentSession, id)
  end

  def find_agent_session_by_name(workspace_id, display_name) do
    repo = JidoMurmur.repo()

    repo.one(
      from as in AgentSession,
        where: as.workspace_id == ^workspace_id and as.display_name == ^display_name
    )
  end

  # Authorization hook — delegates to configured module or no-op
  defp authorize!(action, resource, scope) do
    case Application.get_env(:jido_murmur, :authorize) do
      nil -> :ok
      mod when is_atom(mod) -> mod.authorize!(action, resource, scope)
    end
  end
end
