defmodule JidoMurmur.ConversationProjectorTest do
  use JidoMurmur.Case, async: true

  alias Jido.Signal.ID, as: SignalID
  alias JidoMurmur.ConversationProjector
  alias JidoMurmur.ConversationReadModel

  describe "ConversationReadModel.apply_signal/2" do
    test "content deltas append into one canonical assistant step by request_id" do
      model = ConversationReadModel.new("session-1")

      assert {:ok, model, message} =
               ConversationReadModel.apply_signal(
                 model,
                 Jido.Signal.new!(
                   "ai.llm.delta",
                   %{request_id: "req-1", delta: "Hello", chunk_type: :content},
                   source: "/test"
                 )
               )

      assert message.id == "req-1-step-1"
      assert message.request_id == "req-1"
      assert message.content == "Hello"
      assert message.status == :running

      assert {:ok, model, message} =
               ConversationReadModel.apply_signal(
                 model,
                 Jido.Signal.new!(
                   "ai.llm.delta",
                   %{request_id: "req-1", delta: " world", chunk_type: :content},
                   source: "/test"
                 )
               )

      assert message.content == "Hello world"
      assert length(model.messages) == 1
    end

    test "tool lifecycle merges pending and completed tool calls into the same assistant step" do
      model = ConversationReadModel.new("session-1")

      llm_response =
        Jido.Signal.new!(
          "ai.llm.response",
          %{
            request_id: "req-2",
            result: {:ok, %{tool_calls: [%{id: "call-1", name: "search", arguments: %{query: "elixir"}}]}, []}
          },
          source: "/test"
        )

      assert {:ok, model, message} = ConversationReadModel.apply_signal(model, llm_response)
      assert [%{id: "call-1", name: "search", status: :running}] = message.tool_calls

      tool_result =
        Jido.Signal.new!(
          "ai.tool.result",
          %{
            request_id: "req-2",
            call_id: "call-1",
            tool_name: "search",
            result: {:ok, "3 results", []}
          },
          source: "/test"
        )

      assert {:ok, _model, message} = ConversationReadModel.apply_signal(model, tool_result)

      assert [%{id: "call-1", name: "search", status: :completed, result: result}] = message.tool_calls
      assert result =~ "3 results"
      assert message.id == "req-2-step-1"
    end

    test "tool lifecycle preserves tool call args after completion" do
      model = ConversationReadModel.new("session-1")

      llm_response =
        Jido.Signal.new!(
          "ai.llm.response",
          %{
            request_id: "req-2b",
            result:
              {:ok,
               %{
                 tool_calls: [
                   %{
                     id: "call-keep-args",
                     name: "tell",
                     arguments: %{"target_agent" => "bob", "intent" => "notify", "message" => "hi"}
                   }
                 ]
               }, []}
          },
          source: "/test"
        )

      assert {:ok, model, message} = ConversationReadModel.apply_signal(model, llm_response)

      assert [%{id: "call-keep-args", args: args, status: :running}] = message.tool_calls
      assert args == %{"target_agent" => "bob", "intent" => "notify", "message" => "hi"}

      tool_result =
        Jido.Signal.new!(
          "ai.tool.result",
          %{
            request_id: "req-2b",
            call_id: "call-keep-args",
            tool_name: "tell",
            result: {:ok, %{target: "bob", delivered: true}, []}
          },
          source: "/test"
        )

      assert {:ok, _model, message} = ConversationReadModel.apply_signal(model, tool_result)

      assert [
               %{
                 id: "call-keep-args",
                 name: "tell",
                 args: %{"target_agent" => "bob", "intent" => "notify", "message" => "hi"},
                 status: :completed,
                 result: result
               }
             ] = message.tool_calls

      assert result =~ "delivered"
    end

    test "usage merges across multiple signals for one assistant step" do
      model = ConversationReadModel.new("session-1")

      assert {:ok, model, _message} =
               ConversationReadModel.apply_signal(
                 model,
                 Jido.Signal.new!(
                   "ai.usage",
                   %{
                     request_id: "req-3",
                     input_tokens: 100,
                     output_tokens: 50,
                     total_tokens: 150,
                     duration_ms: 500,
                     model: "gpt-5-mini"
                   },
                   source: "/test"
                 )
               )

      assert {:ok, _model, message} =
               ConversationReadModel.apply_signal(
                 model,
                 Jido.Signal.new!(
                   "ai.usage",
                   %{
                     request_id: "req-3",
                     input_tokens: 200,
                     output_tokens: 80,
                     total_tokens: 280,
                     duration_ms: 700,
                     model: "gpt-5-mini"
                   },
                   source: "/test"
                 )
               )

      assert message.usage.input_tokens == 300
      assert message.usage.output_tokens == 130
      assert message.usage.total_tokens == 430
      assert message.usage.duration_ms == 1200
    end

    test "next llm phase opens a second assistant step for the same request" do
      model = ConversationReadModel.new("session-1")
      timestamp = 1_700_000_000_000

      {:ok, model, _step_one} =
        ConversationReadModel.apply_signal(
          model,
          Jido.Signal.new!(
            "ai.llm.response",
            %{
              request_id: "req-4",
              result: {:ok, %{text: "Need a tool", tool_calls: [%{id: "call-2", name: "search", arguments: %{query: "phoenix"}}]}, []}
            },
            source: "/test",
            id: SignalID.generate_sequential(timestamp, 1)
          )
        )

      {:ok, model, _step_one} =
        ConversationReadModel.apply_signal(
          model,
          Jido.Signal.new!(
            "ai.tool.result",
            %{request_id: "req-4", call_id: "call-2", tool_name: "search", result: {:ok, "done", []}},
            source: "/test",
            id: SignalID.generate_sequential(timestamp, 2)
          )
        )

      {:ok, model, step_two} =
        ConversationReadModel.apply_signal(
          model,
          Jido.Signal.new!(
            "ai.llm.delta",
            %{request_id: "req-4", delta: "Final answer", chunk_type: :content},
            source: "/test",
            id: SignalID.generate_sequential(timestamp, 3)
          )
        )

      assert Enum.map(model.messages, & &1.id) == ["req-4-step-1", "req-4-step-2"]
      assert step_two.id == "req-4-step-2"
    end

    test "conversation projector caches the full read-model snapshot" do
      session_id = Ecto.UUID.generate()
      workspace_id = Ecto.UUID.generate()

      on_exit(fn -> ConversationProjector.clear(session_id) end)

      signal =
        Jido.Signal.new!(
          "ai.llm.delta",
          %{request_id: "req-5", delta: "Hello", chunk_type: :content},
          source: "/test",
          id: SignalID.generate_sequential(1_700_000_000_000, 1)
        )

      assert {:ok, message} =
               ConversationProjector.apply_signal(
                 workspace_id,
                 session_id,
                 %{state: %{__thread__: %{entries: []}}},
                 signal
               )

      assert message.id == "req-5-step-1"

      assert [
               {^session_id, %ConversationReadModel{} = snapshot}
             ] = :ets.lookup(:jido_murmur_conversation_snapshots, session_id)

      assert snapshot.messages == [message]
      assert snapshot.step_indexes == %{"req-5" => 1}
    end
  end
end
