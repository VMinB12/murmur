defmodule JidoMurmur.Workspaces.Workspace do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "jido_murmur_workspaces" do
    field :name, :string
    field :owner_id, :string
    field :metadata, :map, default: %{}
    has_many :agent_sessions, JidoMurmur.Workspaces.AgentSession
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:name, :owner_id, :metadata])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
  end
end
