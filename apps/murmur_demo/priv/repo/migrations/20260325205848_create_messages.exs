defmodule Murmur.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :agent_session_id,
          references(:agent_sessions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :role, :string, null: false
      add :content, :text
      add :sender_name, :string
      add :tool_calls, :map
      add :tool_call_id, :string
      add :metadata, :map, default: %{}

      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:messages, [:agent_session_id])
    create index(:messages, [:agent_session_id, :inserted_at])
  end
end
