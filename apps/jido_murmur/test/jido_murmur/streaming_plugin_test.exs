defmodule JidoMurmur.StreamingPluginTest do
  use JidoMurmur.Case, async: true

  alias JidoMurmur.StreamingPlugin

  defp build_context(session_id, workspace_id) do
    %{agent: %{id: session_id, state: %{workspace_id: workspace_id}}}
  end

  describe "handle_signal/2" do
    test "emits canonical conversation updates instead of raw stream broadcasts" do
      workspace_id = Ecto.UUID.generate()
      session_id = Ecto.UUID.generate()
      request_id = Ecto.UUID.generate()
      stream_topic = "workspace:#{workspace_id}:agent:#{session_id}:stream"
      conversation_topic = JidoMurmur.Topics.agent_conversation(workspace_id, session_id)

      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), stream_topic)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), conversation_topic)

      :ets.insert(:jido_murmur_active_runners, {session_id, request_id})

      on_exit(fn ->
        :ets.delete(:jido_murmur_active_runners, session_id)
        JidoMurmur.ConversationProjector.clear(session_id)
      end)

      signal =
        Jido.Signal.new!(
          "ai.llm.delta",
          %{delta: "Hello", chunk_type: :content},
          source: "/test"
        )

      assert {:ok, :continue} = StreamingPlugin.handle_signal(signal, build_context(session_id, workspace_id))

      refute_receive %Jido.Signal{type: "ai.llm.delta"}, 50

      assert_receive %Jido.Signal{
                       type: "murmur.conversation.updated",
                       data: %{
                         session_id: ^session_id,
                         message: %{id: message_id, request_id: ^request_id, content: "Hello"}
                       }
                     }

      assert message_id == request_id <> "-step-1"
    end

    test "returns continue for non-projecting lifecycle signals without raw broadcast" do
      workspace_id = Ecto.UUID.generate()
      session_id = Ecto.UUID.generate()
      stream_topic = "workspace:#{workspace_id}:agent:#{session_id}:stream"
      conversation_topic = JidoMurmur.Topics.agent_conversation(workspace_id, session_id)

      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), stream_topic)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), conversation_topic)

      signal = Jido.Signal.new!("ai.request.started", %{}, source: "/test")

      assert {:ok, :continue} = StreamingPlugin.handle_signal(signal, build_context(session_id, workspace_id))

      refute_receive %Jido.Signal{}, 50
    end
  end
end
