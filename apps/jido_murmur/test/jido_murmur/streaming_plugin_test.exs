defmodule JidoMurmur.StreamingPluginTest do
  use JidoMurmur.Case, async: true

  alias JidoMurmur.StreamingPlugin

  defp build_context(session_id, workspace_id) do
    %{agent: %{id: session_id, state: %{workspace_id: workspace_id}}}
  end

  describe "handle_signal/2" do
    test "broadcasts signal to PubSub on stream topic" do
      workspace_id = Ecto.UUID.generate()
      session_id = Ecto.UUID.generate()
      topic = StreamingPlugin.stream_topic(workspace_id, session_id)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), topic)

      signal = %{type: "ai.llm.delta", data: %{content: "Hello"}}

      assert {:ok, :continue} = StreamingPlugin.handle_signal(signal, build_context(session_id, workspace_id))

      assert_receive {:agent_signal, ^session_id, ^signal}
    end

    test "handles ai.llm.response signal" do
      workspace_id = Ecto.UUID.generate()
      session_id = Ecto.UUID.generate()
      topic = StreamingPlugin.stream_topic(workspace_id, session_id)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), topic)

      signal = %{type: "ai.llm.response", data: %{content: "Full response"}}

      assert {:ok, :continue} = StreamingPlugin.handle_signal(signal, build_context(session_id, workspace_id))

      assert_receive {:agent_signal, ^session_id, ^signal}
    end

    test "handles ai.tool.result signal" do
      workspace_id = Ecto.UUID.generate()
      session_id = Ecto.UUID.generate()
      topic = StreamingPlugin.stream_topic(workspace_id, session_id)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), topic)

      signal = %{type: "ai.tool.result", data: %{tool: "search", result: "found"}}

      assert {:ok, :continue} = StreamingPlugin.handle_signal(signal, build_context(session_id, workspace_id))

      assert_receive {:agent_signal, ^session_id, ^signal}
    end

    test "handles ai.request.started signal" do
      workspace_id = Ecto.UUID.generate()
      session_id = Ecto.UUID.generate()
      topic = StreamingPlugin.stream_topic(workspace_id, session_id)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), topic)

      signal = %{type: "ai.request.started", data: %{}}

      assert {:ok, :continue} = StreamingPlugin.handle_signal(signal, build_context(session_id, workspace_id))

      assert_receive {:agent_signal, ^session_id, ^signal}
    end

    test "handles ai.request.failed signal" do
      workspace_id = Ecto.UUID.generate()
      session_id = Ecto.UUID.generate()
      topic = StreamingPlugin.stream_topic(workspace_id, session_id)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), topic)

      signal = %{type: "ai.request.failed", data: %{error: "timeout"}}

      assert {:ok, :continue} = StreamingPlugin.handle_signal(signal, build_context(session_id, workspace_id))

      assert_receive {:agent_signal, ^session_id, ^signal}
    end
  end

  describe "stream_topic/2" do
    test "returns workspace-scoped topic" do
      assert StreamingPlugin.stream_topic("ws-1", "abc-123") ==
               "workspace:ws-1:agent:abc-123:stream"
    end
  end
end
