defmodule Murmur.Chat do
  @moduledoc "Context for managing chat messages."

  import Ecto.Query
  alias Murmur.Chat.Message
  alias Murmur.Repo

  def list_messages(agent_session_id) do
    Repo.all(
      from m in Message,
        where: m.agent_session_id == ^agent_session_id,
        order_by: [asc: m.inserted_at]
    )
  end

  def create_message(attrs) do
    %Message{}
    |> Message.changeset(attrs)
    |> Ecto.Changeset.put_change(:inserted_at, DateTime.utc_now())
    |> Repo.insert()
  end

  def persist_turn(agent_session_id, messages) when is_list(messages) do
    now = DateTime.utc_now()

    entries =
      messages
      |> Enum.with_index()
      |> Enum.map(fn {msg, idx} ->
        %{
          id: Ecto.UUID.generate(),
          agent_session_id: agent_session_id,
          role: msg.role,
          content: msg[:content],
          sender_name: msg[:sender_name],
          tool_calls: msg[:tool_calls],
          tool_call_id: msg[:tool_call_id],
          metadata: msg[:metadata] || %{},
          inserted_at: DateTime.add(now, idx, :microsecond)
        }
      end)

    Repo.insert_all(Message, entries)
  end
end
