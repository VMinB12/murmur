defmodule JidoMurmur.Workspaces.AgentSession do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "jido_murmur_agent_sessions" do
    field :agent_profile_id, :string
    field :display_name, :string
    field :status, Ecto.Enum, values: [:idle, :busy], default: :idle
    field :owner_id, :string
    field :metadata, :map, default: %{}
    belongs_to :workspace, JidoMurmur.Workspaces.Workspace
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(agent_session, attrs) do
    agent_session
    |> cast(attrs, [:agent_profile_id, :display_name, :status, :owner_id, :metadata])
    |> validate_required([:agent_profile_id, :display_name])
    |> validate_length(:display_name, max: 255)
    |> unique_constraint([:workspace_id, :display_name])
  end
end
