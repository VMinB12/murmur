defmodule Murmur.Repo.Migrations.CreateJidoThreadEntries do
  use Ecto.Migration

  def change do
    create table(:jido_thread_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :thread_id, :string, null: false
      add :seq, :integer, null: false
      add :kind, :string, null: false
      add :payload, :map, default: %{}
      add :refs, :map, default: %{}
      add :at, :bigint, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:jido_thread_entries, [:thread_id, :seq])
    create index(:jido_thread_entries, [:thread_id])
  end
end
