defmodule JidoMurmur.ConversationReadModelTest do
  use JidoMurmur.Case, async: true

  alias Jido.Signal.ID, as: SignalID
  alias JidoMurmur.ConversationReadModel
  alias JidoMurmur.DisplayMessage

  describe "new/2" do
    test "sorts messages by canonical first-seen ordering" do
      later = DisplayMessage.user("later", first_seen_at: 200, first_seen_seq: 2)
      earlier = DisplayMessage.assistant("earlier", first_seen_at: 100, first_seen_seq: 1)

      model = ConversationReadModel.new("session-1", [later, earlier])

      assert Enum.map(model.messages, & &1.content) == ["earlier", "later"]
    end
  end

  describe "from_entries/2" do
    test "derives assistant-step ordering from persisted entry timestamps and sequence" do
      entries = [
        %{
          id: "entry-1",
          seq: 7,
          at: 1_000,
          kind: :message,
          payload: %{role: "user", content: "Hello"}
        },
        %{
          id: "entry-2",
          seq: 8,
          at: 2_000,
          kind: :ai_message,
          payload: %{role: "assistant", content: "Hi there", request_id: "req-1"}
        }
      ]

      model = ConversationReadModel.from_entries("session-1", entries)

      assert [user_message, assistant_message] = model.messages
      assert user_message.first_seen_at == 1_000
      assert user_message.first_seen_seq == 7
      assert assistant_message.id == "req-1-step-1"
      assert assistant_message.first_seen_at == 2_000
      assert assistant_message.first_seen_seq == 8
      assert assistant_message.step_index == 1
    end

    test "reconstructs multiple assistant steps for one outer request" do
      entries = [
        %{
          id: "assistant-step-1",
          seq: 1,
          at: 1_000,
          kind: :ai_message,
          payload: %{
            role: "assistant",
            content: "Searching",
            request_id: "req-1",
            tool_calls: [%{id: "call-1", name: "search", arguments: %{query: "elixir"}}]
          }
        },
        %{
          id: "tool-result-1",
          seq: 2,
          at: 1_100,
          kind: :ai_message,
          payload: %{
            role: "tool",
            content: "3 results",
            tool_call_id: "call-1",
            request_id: "req-1"
          }
        },
        %{
          id: "assistant-step-2",
          seq: 3,
          at: 2_000,
          kind: :ai_message,
          payload: %{role: "assistant", content: "Final answer", request_id: "req-1"}
        }
      ]

      model = ConversationReadModel.from_entries("session-1", entries)

      assert [step_one, step_two] = model.messages
      assert step_one.id == "req-1-step-1"
      assert step_one.step_index == 1
      assert [%{id: "call-1", result: "3 results", status: :completed}] = step_one.tool_calls
      assert step_one.status == :completed

      assert step_two.id == "req-1-step-2"
      assert step_two.step_index == 2
      assert step_two.content == "Final answer"
    end

    test "reuses visible ingress identity refs for persisted user messages" do
      message_id = SignalID.generate_sequential(1_700_000_000_000, 7)

      entries = [
        %{
          id: "storage-entry-1",
          seq: 2,
          at: 999,
          kind: :message,
          payload: %{role: "user", content: "Hello again"},
          refs: %{
            message_id: message_id,
            message_first_seen_at: SignalID.extract_timestamp(message_id),
            message_first_seen_seq: SignalID.sequence_number(message_id)
          }
        }
      ]

      model = ConversationReadModel.from_entries("session-1", entries)

      assert [user_message] = model.messages
      assert user_message.id == message_id
      assert user_message.first_seen_at == SignalID.extract_timestamp(message_id)
      assert user_message.first_seen_seq == SignalID.sequence_number(message_id)
    end
  end

  describe "apply_signal/2" do
    test "preserves the initial first-seen ordering for a live turn across later updates" do
      timestamp = 1_700_000_000_000

      first_signal =
        Jido.Signal.new!(
          "ai.llm.delta",
          %{request_id: "req-1", delta: "Hello", chunk_type: :content},
          source: "/test",
          id: SignalID.generate_sequential(timestamp, 1)
        )

      second_signal =
        Jido.Signal.new!(
          "ai.llm.delta",
          %{request_id: "req-1", delta: " world", chunk_type: :content},
          source: "/test",
          id: SignalID.generate_sequential(timestamp, 2)
        )

      model = ConversationReadModel.new("session-1")

      assert {:ok, model, first_message} = ConversationReadModel.apply_signal(model, first_signal)
      assert first_message.first_seen_at == timestamp
      assert first_message.first_seen_seq == 1

      assert {:ok, _model, second_message} = ConversationReadModel.apply_signal(model, second_signal)
      assert second_message.content == "Hello world"
      assert second_message.first_seen_at == timestamp
      assert second_message.first_seen_seq == 1
    end

    test "opens a new assistant step after tool execution for the same request" do
      timestamp = 1_700_000_000_000
      model = ConversationReadModel.new("session-1")

      first_delta =
        Jido.Signal.new!(
          "ai.llm.delta",
          %{request_id: "req-1", delta: "Searching", chunk_type: :content},
          source: "/test",
          id: SignalID.generate_sequential(timestamp, 1)
        )

      tool_response =
        Jido.Signal.new!(
          "ai.llm.response",
          %{
            request_id: "req-1",
            result: {:ok, %{text: "Searching", tool_calls: [%{id: "call-1", name: "search", arguments: %{q: "elixir"}}]}, []}
          },
          source: "/test",
          id: SignalID.generate_sequential(timestamp, 2)
        )

      tool_result =
        Jido.Signal.new!(
          "ai.tool.result",
          %{request_id: "req-1", call_id: "call-1", tool_name: "search", result: {:ok, "3 results", []}},
          source: "/test",
          id: SignalID.generate_sequential(timestamp, 3)
        )

      second_delta =
        Jido.Signal.new!(
          "ai.llm.delta",
          %{request_id: "req-1", delta: "Final answer", chunk_type: :content},
          source: "/test",
          id: SignalID.generate_sequential(timestamp, 4)
        )

      {:ok, model, _step_one} = ConversationReadModel.apply_signal(model, first_delta)
      {:ok, model, _step_one} = ConversationReadModel.apply_signal(model, tool_response)
      {:ok, model, step_one} = ConversationReadModel.apply_signal(model, tool_result)
      {:ok, model, step_two} = ConversationReadModel.apply_signal(model, second_delta)

      assert step_one.id == "req-1-step-1"
      assert step_one.status == :completed
      assert [%{id: "call-1", status: :completed}] = step_one.tool_calls

      assert step_two.id == "req-1-step-2"
      assert step_two.step_index == 2
      assert step_two.content == "Final answer"
      assert step_two.first_seen_seq == 4
      assert length(model.messages) == 2
      assert Enum.map(model.messages, & &1.id) == ["req-1-step-1", "req-1-step-2"]
    end
  end
end
