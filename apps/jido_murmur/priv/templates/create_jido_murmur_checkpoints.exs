defmodule <%= @migration_module %>.CreateJidoMurmurCheckpoints do
  use Ecto.Migration

  def change do
    create table(:jido_murmur_checkpoints, primary_key: false) do
      add :key, :string, primary_key: true
      add :data, :map, null: false

      timestamps(type: :utc_datetime_usec)
    end
  end
end
