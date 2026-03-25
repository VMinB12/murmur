defmodule Murmur.Workspaces do
  @moduledoc "Context for managing workspaces and agent sessions."

  import Ecto.Query
  alias Murmur.Repo
  alias Murmur.Workspaces.{AgentSession, Workspace}

  @max_agents_per_workspace 8

  def create_workspace(attrs) do
    %Workspace{}
    |> Workspace.changeset(attrs)
    |> Repo.insert()
  end

  def get_workspace!(id), do: Repo.get!(Workspace, id)

  def list_workspaces do
    Repo.all(from w in Workspace, order_by: [desc: w.inserted_at])
  end

  def list_agent_sessions(workspace_id) do
    Repo.all(
      from as in AgentSession,
        where: as.workspace_id == ^workspace_id,
        order_by: [asc: as.inserted_at]
    )
  end

  def create_agent_session(workspace_id, attrs) do
    session_count =
      Repo.one(
        from as in AgentSession,
          where: as.workspace_id == ^workspace_id,
          select: count(as.id)
      )

    if session_count >= @max_agents_per_workspace do
      {:error, :max_agents_reached}
    else
      %AgentSession{workspace_id: workspace_id}
      |> AgentSession.changeset(attrs)
      |> Repo.insert()
    end
  end

  def delete_agent_session(%AgentSession{} = session) do
    Repo.delete(session)
  end

  def get_agent_session!(id), do: Repo.get!(AgentSession, id)

  def find_agent_session_by_name(workspace_id, display_name) do
    Repo.one(
      from as in AgentSession,
        where: as.workspace_id == ^workspace_id and as.display_name == ^display_name
    )
  end
end
