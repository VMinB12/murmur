defmodule MyApp.Repo.Migrations.CreateJidoMurmurWorkspaces do
  use Ecto.Migration

  def change do
    create table(:jido_murmur_workspaces, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :owner_id, :string
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:jido_murmur_workspaces, [:owner_id])
  end
end
