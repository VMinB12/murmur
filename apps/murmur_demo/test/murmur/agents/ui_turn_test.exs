defmodule JidoMurmur.UITurnTest do
  use ExUnit.Case, async: true

  alias JidoMurmur.UITurn
  alias JidoMurmur.UITurn.ToolCall

  describe "project_entries/1" do
    test "converts a simple user + assistant exchange" do
      entries = [
        entry(:ai_message, %{role: :user, content: "Hello", request_id: "r1"}),
        entry(:ai_message, %{role: :assistant, content: "Hi there!", request_id: "r1"})
      ]

      result = UITurn.project_entries(entries)

      assert [user, assistant] = result
      assert user.role == "user"
      assert user.content == "Hello"
      assert user.sender_name == "You"
      assert assistant.role == "assistant"
      assert assistant.content == "Hi there!"
      assert assistant.tool_calls == []
      assert assistant.thinking == nil
    end

    test "groups assistant + tool entries from the same request" do
      entries = [
        entry(:ai_message, %{role: :user, content: "Ask Bob", request_id: "r1"}),
        entry(:ai_message, %{
          role: :assistant,
          content: "",
          tool_calls: [%{id: "tc1", name: "tell", arguments: %{target: "Bob", message: "hi"}}],
          request_id: "r1"
        }),
        entry(:ai_message, %{
          role: :tool,
          content: "delivered to Bob",
          tool_call_id: "tc1",
          name: "tell",
          request_id: "r1"
        }),
        entry(:ai_message, %{
          role: :assistant,
          content: "I asked Bob for you.",
          request_id: "r1"
        })
      ]

      result = UITurn.project_entries(entries)

      assert [_user, turn] = result
      assert turn.role == "assistant"
      assert turn.content == "I asked Bob for you."
      assert [tc] = turn.tool_calls
      assert %ToolCall{name: "tell", status: :completed, result: "delivered to Bob"} = tc
      assert tc.args == %{target: "Bob", message: "hi"}
    end

    test "preserves thinking content" do
      entries = [
        entry(:ai_message, %{
          role: :assistant,
          content: "The answer is 42.",
          thinking: "Let me reason about this step by step...",
          request_id: "r1"
        })
      ]

      result = UITurn.project_entries(entries)

      assert [turn] = result
      assert turn.thinking == "Let me reason about this step by step..."
      assert turn.content == "The answer is 42."
    end

    test "handles tool call with no result yet (running)" do
      entries = [
        entry(:ai_message, %{
          role: :assistant,
          content: "",
          tool_calls: [%{id: "tc1", name: "tell", arguments: %{}}],
          request_id: "r1"
        })
      ]

      result = UITurn.project_entries(entries)

      assert [turn] = result
      assert [tc] = turn.tool_calls
      assert tc.status == :running
      assert tc.result == nil
    end

    test "handles multiple requests in sequence" do
      entries = [
        entry(:ai_message, %{role: :user, content: "First Q", request_id: "r1"}),
        entry(:ai_message, %{role: :assistant, content: "First A", request_id: "r1"}),
        entry(:ai_message, %{role: :user, content: "Second Q", request_id: "r2"}),
        entry(:ai_message, %{role: :assistant, content: "Second A", request_id: "r2"})
      ]

      result = UITurn.project_entries(entries)

      assert [u1, a1, u2, a2] = result
      assert u1.content == "First Q"
      assert a1.content == "First A"
      assert u2.content == "Second Q"
      assert a2.content == "Second A"
    end

    test "returns empty list for empty entries" do
      assert UITurn.project_entries([]) == []
    end

    test "filters out non-message entries" do
      entries = [
        %{kind: :system, id: "sys1", payload: %{content: "system msg"}},
        entry(:ai_message, %{role: :user, content: "Hello", request_id: "r1"})
      ]

      result = UITurn.project_entries(entries)
      assert [user] = result
      assert user.content == "Hello"
    end

    test "infers sender name from inter-agent message prefix" do
      entries = [
        entry(:ai_message, %{role: :user, content: "[alice]: User says hi", request_id: "r1"})
      ]

      result = UITurn.project_entries(entries)
      assert [user] = result
      assert user.sender_name == "alice"
      assert user.content == "[alice]: User says hi"
    end

    test "also supports legacy kind: :message entries" do
      entries = [
        entry(:message, %{role: "user", content: "Legacy", sender_name: "You"}),
        entry(:ai_message, %{role: :assistant, content: "Reply", request_id: "r1"})
      ]

      result = UITurn.project_entries(entries)
      assert [user, assistant] = result
      assert user.role == "user"
      assert user.content == "Legacy"
      assert user.sender_name == "You"
      assert assistant.content == "Reply"
    end
  end

  # Helper to build mock thread entries
  defp entry(kind, payload) do
    %{
      id: Ecto.UUID.generate(),
      kind: kind,
      payload: payload,
      refs: %{}
    }
  end
end
