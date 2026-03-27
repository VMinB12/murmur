defmodule Murmur.Tasks.Task do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tasks" do
    field :title, :string
    field :description, :string
    field :assignee, :string
    field :status, Ecto.Enum, values: [:todo, :in_progress, :done, :aborted], default: :todo
    field :created_by, :string

    belongs_to :workspace, Murmur.Workspaces.Workspace

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :description, :assignee, :status])
    |> validate_required([:title, :assignee])
    |> validate_length(:title, max: 200)
    |> validate_length(:description, max: 2000)
    |> validate_inclusion(:status, [:todo, :in_progress, :done, :aborted])
  end

  def update_changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :description, :status])
    |> validate_length(:title, max: 200)
    |> validate_length(:description, max: 2000)
    |> validate_inclusion(:status, [:todo, :in_progress, :done, :aborted])
  end
end
