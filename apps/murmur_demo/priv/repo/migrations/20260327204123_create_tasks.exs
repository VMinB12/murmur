defmodule Murmur.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :title, :string, null: false
      add :description, :text
      add :assignee, :string, null: false
      add :status, :string, null: false, default: "todo"
      add :created_by, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:tasks, [:workspace_id])
    create index(:tasks, [:workspace_id, :status])
  end
end
