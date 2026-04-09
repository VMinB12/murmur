defmodule JidoMurmur.ConversationSnapshotSourceTest do
  use JidoMurmur.Case, async: true

  alias Jido.Signal.ID, as: SignalID
  alias JidoMurmur.ConversationSnapshotSource
  alias JidoMurmur.Workspaces

  setup do
    {:ok, workspace} = Workspaces.create_workspace(%{name: "Snapshot Source WS"})

    {:ok, session} =
      Workspaces.create_agent_session(workspace.id, %{
        agent_profile_id: "general_agent",
        display_name: "Source Bot"
      })

    %{workspace: workspace, session: session}
  end

  test "from_agent/1 exposes live thread entries with revision metadata" do
    message_id = SignalID.generate_sequential(1_700_000_000_000, 2)

    agent = %{
      state: %{
        __thread__: %{
          rev: 1,
          entries: [
            %{
              id: message_id,
              seq: 1,
              at: SignalID.extract_timestamp(message_id),
              kind: :message,
              payload: %{role: "user", content: "hi"},
              refs: %{message_id: message_id}
            }
          ]
        }
      }
    }

    assert %ConversationSnapshotSource{source: :live_thread, persisted_rev: 1, entries: [entry]} =
             ConversationSnapshotSource.from_agent(agent)

    assert entry.kind == :message
  end

  test "load/1 falls back to persisted thread history when no live agent exists", %{session: session} do
    {adapter, opts} = JidoMurmur.jido_mod().__jido_storage__()

    assert {:ok, _thread} =
             adapter.append_thread(session.id, [
               %{kind: :message, payload: %{role: "user", content: "persisted"}, refs: %{}}
             ], opts)

    assert %ConversationSnapshotSource{source: :storage, persisted_rev: 1, entries: [entry]} =
             ConversationSnapshotSource.load(session)

    assert entry.payload["content"] == "persisted"
  end
end
