defmodule Murmur.Repo.Migrations.DropMessages do
  use Ecto.Migration

  def change do
    drop table(:messages)
  end
end
