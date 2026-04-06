defmodule JidoMurmur.ConversationProjectorTest do
  use JidoMurmur.Case, async: true

  alias JidoMurmur.ConversationReadModel

  describe "ConversationReadModel.apply_signal/2" do
    test "content deltas append into one canonical turn by request_id" do
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

      assert message.id == "req-1-turn"
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

    test "tool lifecycle merges pending and completed tool calls into the same turn" do
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
    end

    test "usage merges across multiple signals for one turn" do
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
  end
end
