defmodule Murmur.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messages" do
    field :role, :string
    field :content, :string
    field :sender_name, :string
    field :tool_calls, :map
    field :tool_call_id, :string
    field :metadata, :map, default: %{}

    belongs_to :agent_session, Murmur.Workspaces.AgentSession

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :sender_name, :tool_calls, :tool_call_id, :metadata])
    |> validate_required([:role])
    |> validate_inclusion(:role, ["user", "assistant", "tool_call", "tool_result"])
  end
end
