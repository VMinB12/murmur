defmodule Murmur.Workspaces.AgentSession do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agent_sessions" do
    field :agent_profile_id, :string
    field :display_name, :string
    field :status, :string, default: "idle"

    belongs_to :workspace, Murmur.Workspaces.Workspace

    has_many :messages, Murmur.Chat.Message

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(agent_session, attrs) do
    agent_session
    |> cast(attrs, [:agent_profile_id, :display_name, :status])
    |> validate_required([:agent_profile_id, :display_name])
    |> validate_length(:display_name, max: 255)
    |> validate_inclusion(:status, ["idle", "busy"])
    |> unique_constraint([:workspace_id, :display_name])
  end
end
