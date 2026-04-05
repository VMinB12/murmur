defmodule JidoMurmur.Ingress.InputTest do
  use JidoMurmur.Case, async: false

  alias JidoMurmur.ActorIdentity
  alias JidoMurmur.Ingress.Input

  describe "direct_message/3" do
    test "builds a human ingress input for direct workspace messages" do
      session = build_session()

      assert {:ok, input} = Input.direct_message(session, "  hello world  ")

      assert input.content == "hello world"
      assert input.source == %{kind: :human, via: :workspace_live}
      assert input.refs.hop_count == 0
      assert input.refs.origin_actor == %{kind: :human}
      assert input.refs.workspace_id == session.workspace_id
      assert is_binary(input.refs.interaction_id)
      assert Input.control_kind(input) == :steer
    end
  end

  describe "programmatic_message/3" do
    test "builds a programmatic ingress input for inter-agent follow-ups" do
      session = build_session()

      assert {:ok, input} =
               Input.programmatic_message(session, "follow up",
                 via: :steering,
                 origin_actor: ActorIdentity.agent("Alice"),
                 sender_trace_id: "trace-123",
                 refs: %{hop_count: 1}
               )

      assert input.source == %{kind: :programmatic, via: :steering}
      assert input.refs.hop_count == 1
      assert input.refs.sender_name == "Alice"
      assert input.refs.origin_actor == %{kind: :agent, name: "Alice"}
      assert input.refs.sender_trace_id == "trace-123"
      assert input.refs.workspace_id == session.workspace_id
      assert is_binary(input.refs.interaction_id)
      assert Input.control_kind(input) == :inject
    end
  end

  describe "new/2 validation" do
    test "rejects missing source" do
      assert {:error, :missing_source} =
               Input.new("hello", refs: %{interaction_id: "i-1", workspace_id: "w-1"})
    end

    test "rejects missing interaction metadata" do
      assert {:error, :missing_interaction_id} =
               Input.new("hello", source: %{kind: :human, via: :test}, refs: %{workspace_id: "w-1"})

      assert {:error, :missing_workspace_id} =
               Input.new("hello", source: %{kind: :human, via: :test}, refs: %{interaction_id: "i-1"})
    end

    test "rejects invalid optional ref types" do
      assert {:error, :invalid_sender_name} =
               Input.new("hello",
                 source: %{kind: :programmatic, via: :test},
                 refs: %{interaction_id: "i-1", workspace_id: "w-1", sender_name: 123}
               )

      assert {:error, :invalid_origin_actor} =
               Input.new("hello",
                 source: %{kind: :programmatic, via: :test},
                 refs: %{interaction_id: "i-1", workspace_id: "w-1", origin_actor: %{kind: 123}}
               )

      assert {:error, :invalid_sender_trace_id} =
               Input.new("hello",
                 source: %{kind: :programmatic, via: :test},
                 refs: %{interaction_id: "i-1", workspace_id: "w-1", sender_trace_id: 123}
               )

      assert {:error, :invalid_hop_count} =
               Input.new("hello",
                 source: %{kind: :programmatic, via: :test},
                 refs: %{interaction_id: "i-1", workspace_id: "w-1", hop_count: -1}
               )
    end

    test "rejects source maps without via metadata" do
      assert {:error, :invalid_source} =
               Input.new("hello", source: %{kind: :human}, refs: %{interaction_id: "i-1", workspace_id: "w-1"})
    end

    test "rejects string-key metadata refs" do
      assert {:error, :invalid_refs} =
               Input.new("hello",
                 source: %{kind: :human, via: :test},
                 refs: %{"interaction_id" => "i-1", workspace_id: "w-1"}
               )
    end
  end

  defp build_session do
    %JidoMurmur.Workspaces.AgentSession{
      id: Ecto.UUID.generate(),
      workspace_id: Ecto.UUID.generate(),
      agent_profile_id: "test_agent",
      display_name: "Test Agent",
      status: :idle
    }
  end
end
