defmodule JidoMurmur.StreamingPluginTest do
  use JidoMurmur.Case, async: true

  alias JidoMurmur.StreamingPlugin

  describe "handle_signal/2" do
    test "broadcasts signal to PubSub on stream topic" do
      session_id = Ecto.UUID.generate()
      topic = StreamingPlugin.stream_topic(session_id)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), topic)

      signal = %{type: "ai.llm.delta", data: %{content: "Hello"}}
      context = %{agent: %{id: session_id}}

      assert {:ok, :continue} = StreamingPlugin.handle_signal(signal, context)

      assert_receive {:agent_signal, ^session_id, ^signal}
    end

    test "handles ai.llm.response signal" do
      session_id = Ecto.UUID.generate()
      topic = StreamingPlugin.stream_topic(session_id)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), topic)

      signal = %{type: "ai.llm.response", data: %{content: "Full response"}}
      context = %{agent: %{id: session_id}}

      assert {:ok, :continue} = StreamingPlugin.handle_signal(signal, context)

      assert_receive {:agent_signal, ^session_id, ^signal}
    end

    test "handles ai.tool.result signal" do
      session_id = Ecto.UUID.generate()
      topic = StreamingPlugin.stream_topic(session_id)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), topic)

      signal = %{type: "ai.tool.result", data: %{tool: "search", result: "found"}}
      context = %{agent: %{id: session_id}}

      assert {:ok, :continue} = StreamingPlugin.handle_signal(signal, context)

      assert_receive {:agent_signal, ^session_id, ^signal}
    end

    test "handles ai.request.started signal" do
      session_id = Ecto.UUID.generate()
      topic = StreamingPlugin.stream_topic(session_id)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), topic)

      signal = %{type: "ai.request.started", data: %{}}
      context = %{agent: %{id: session_id}}

      assert {:ok, :continue} = StreamingPlugin.handle_signal(signal, context)

      assert_receive {:agent_signal, ^session_id, ^signal}
    end

    test "handles ai.request.failed signal" do
      session_id = Ecto.UUID.generate()
      topic = StreamingPlugin.stream_topic(session_id)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), topic)

      signal = %{type: "ai.request.failed", data: %{error: "timeout"}}
      context = %{agent: %{id: session_id}}

      assert {:ok, :continue} = StreamingPlugin.handle_signal(signal, context)

      assert_receive {:agent_signal, ^session_id, ^signal}
    end
  end

  describe "stream_topic/1" do
    test "returns session-scoped topic" do
      assert StreamingPlugin.stream_topic("abc-123") == "agent_stream:abc-123"
    end
  end
end
