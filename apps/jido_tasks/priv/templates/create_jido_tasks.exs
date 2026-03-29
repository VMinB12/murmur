defmodule <%= @migration_module %>.CreateJidoTasks do
  use Ecto.Migration

  def change do
    create table(:jido_tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :workspace_id, references(:jido_murmur_workspaces, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :string, null: false, size: 200
      add :description, :string, size: 2000
      add :assignee, :string, null: false
      add :status, :string, null: false, default: "todo"
      add :created_by, :string, null: false
      add :owner_id, :string
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:jido_tasks, [:workspace_id])
    create index(:jido_tasks, [:workspace_id, :status])
  end
end
