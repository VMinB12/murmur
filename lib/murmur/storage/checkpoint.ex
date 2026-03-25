defmodule Murmur.Storage.Checkpoint do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:key, :string, autogenerate: false}

  schema "jido_checkpoints" do
    field :data, :map

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(checkpoint, attrs) do
    checkpoint
    |> cast(attrs, [:key, :data])
    |> validate_required([:key, :data])
  end
end
