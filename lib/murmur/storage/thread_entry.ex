defmodule Murmur.Storage.ThreadEntry do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "jido_thread_entries" do
    field :thread_id, :string
    field :seq, :integer
    field :kind, :string
    field :payload, :map, default: %{}
    field :refs, :map, default: %{}
    field :at, :integer

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:thread_id, :seq, :kind, :payload, :refs, :at])
    |> validate_required([:thread_id, :seq, :kind, :at])
    |> unique_constraint([:thread_id, :seq])
  end
end
