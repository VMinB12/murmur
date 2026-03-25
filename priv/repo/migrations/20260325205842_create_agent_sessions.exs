defmodule Murmur.Repo.Migrations.CreateAgentSessions do
  use Ecto.Migration

  def change do
    create table(:agent_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :agent_profile_id, :string, null: false
      add :display_name, :string, null: false
      add :status, :string, null: false, default: "idle"

      timestamps(type: :utc_datetime_usec)
    end

    create index(:agent_sessions, [:workspace_id])
    create unique_index(:agent_sessions, [:workspace_id, :display_name])
  end
end
