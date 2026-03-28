defmodule <%= @migration_module %>.CreateJidoMurmurAgentSessions do
  use Ecto.Migration

  def change do
    create table(:jido_murmur_agent_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :workspace_id, references(:jido_murmur_workspaces, type: :binary_id, on_delete: :delete_all), null: false
      add :agent_profile_id, :string, null: false
      add :display_name, :string, null: false
      add :status, :string, default: "idle", null: false
      add :owner_id, :string
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:jido_murmur_agent_sessions, [:workspace_id])
    create unique_index(:jido_murmur_agent_sessions, [:workspace_id, :display_name])
  end
end
