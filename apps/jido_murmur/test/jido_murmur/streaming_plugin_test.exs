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

      signal = Jido.Signal.new!("ai.llm.delta", %{content: "Hello"}, source: "/test")

      assert {:ok, :continue} = StreamingPlugin.handle_signal(signal, build_context(session_id, workspace_id))

      assert_receive %Jido.Signal{type: "ai.llm.delta", subject: "/agents/" <> _}
    end

    test "handles ai.llm.response signal" do
      workspace_id = Ecto.UUID.generate()
      session_id = Ecto.UUID.generate()
      topic = StreamingPlugin.stream_topic(workspace_id, session_id)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), topic)

      signal = Jido.Signal.new!("ai.llm.response", %{content: "Full response"}, source: "/test")

      assert {:ok, :continue} = StreamingPlugin.handle_signal(signal, build_context(session_id, workspace_id))

      assert_receive %Jido.Signal{type: "ai.llm.response", subject: "/agents/" <> _}
    end

    test "handles ai.tool.result signal" do
      workspace_id = Ecto.UUID.generate()
      session_id = Ecto.UUID.generate()
      topic = StreamingPlugin.stream_topic(workspace_id, session_id)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), topic)

      signal = Jido.Signal.new!("ai.tool.result", %{tool: "search", result: "found"}, source: "/test")

      assert {:ok, :continue} = StreamingPlugin.handle_signal(signal, build_context(session_id, workspace_id))

      assert_receive %Jido.Signal{type: "ai.tool.result", subject: "/agents/" <> _}
    end

    test "handles ai.tool.started signal" do
      workspace_id = Ecto.UUID.generate()
      session_id = Ecto.UUID.generate()
      topic = StreamingPlugin.stream_topic(workspace_id, session_id)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), topic)

      signal =
        Jido.Signal.new!("ai.tool.started", %{tool_name: "search", arguments: %{query: "phoenix"}},
          source: "/test"
        )

      assert {:ok, :continue} = StreamingPlugin.handle_signal(signal, build_context(session_id, workspace_id))

      assert_receive %Jido.Signal{type: "ai.tool.started", subject: "/agents/" <> _}
    end

    test "handles ai.request.started signal" do
      workspace_id = Ecto.UUID.generate()
      session_id = Ecto.UUID.generate()
      topic = StreamingPlugin.stream_topic(workspace_id, session_id)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), topic)

      signal = Jido.Signal.new!("ai.request.started", %{}, source: "/test")

      assert {:ok, :continue} = StreamingPlugin.handle_signal(signal, build_context(session_id, workspace_id))

      assert_receive %Jido.Signal{type: "ai.request.started", subject: "/agents/" <> _}
    end

    test "handles ai.request.failed signal" do
      workspace_id = Ecto.UUID.generate()
      session_id = Ecto.UUID.generate()
      topic = StreamingPlugin.stream_topic(workspace_id, session_id)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), topic)

      signal = Jido.Signal.new!("ai.request.failed", %{error: "timeout"}, source: "/test")

      assert {:ok, :continue} = StreamingPlugin.handle_signal(signal, build_context(session_id, workspace_id))

      assert_receive %Jido.Signal{type: "ai.request.failed", subject: "/agents/" <> _}
    end

    test "preserves existing subject if already set" do
      workspace_id = Ecto.UUID.generate()
      session_id = Ecto.UUID.generate()
      topic = StreamingPlugin.stream_topic(workspace_id, session_id)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), topic)

      signal = Jido.Signal.new!("ai.llm.delta", %{content: "Hello"}, source: "/test", subject: "/custom/subject")

      assert {:ok, :continue} = StreamingPlugin.handle_signal(signal, build_context(session_id, workspace_id))

      assert_receive %Jido.Signal{type: "ai.llm.delta", subject: "/custom/subject"}
    end
  end

  describe "stream_topic/2" do
    test "returns workspace-scoped topic" do
      assert StreamingPlugin.stream_topic("ws-1", "abc-123") ==
               "workspace:ws-1:agent:abc-123:stream"
    end
  end
end
