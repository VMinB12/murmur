defmodule JidoTasks.Task do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type status :: :todo | :in_progress | :done | :aborted

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          assignee: String.t() | nil,
          status: status(),
          created_by: String.t() | nil,
          owner_id: String.t() | nil,
          metadata: map(),
          workspace_id: Ecto.UUID.t() | nil,
          workspace: term(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "jido_tasks" do
    field :title, :string
    field :description, :string
    field :assignee, :string
    field :status, Ecto.Enum, values: [:todo, :in_progress, :done, :aborted], default: :todo
    field :created_by, :string
    field :owner_id, :string
    field :metadata, :map, default: %{}

    belongs_to :workspace, JidoMurmur.Workspaces.Workspace

    timestamps(type: :utc_datetime_usec)
  end

  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :description, :assignee, :status])
    |> validate_required([:title, :assignee])
    |> validate_length(:title, max: 200)
    |> validate_length(:description, max: 2000)
    |> validate_inclusion(:status, [:todo, :in_progress, :done, :aborted])
  end

  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :description, :status])
    |> validate_length(:title, max: 200)
    |> validate_length(:description, max: 2000)
    |> validate_inclusion(:status, [:todo, :in_progress, :done, :aborted])
  end
end
