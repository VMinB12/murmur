defmodule JidoMurmur.UITurnTest do
  use ExUnit.Case, async: true

  alias JidoMurmur.UITurn

  describe "project_entries/1" do
    test "returns empty list for empty input" do
      assert UITurn.project_entries([]) == []
    end

    test "projects a single user message" do
      entries = [
        %{
          id: "msg-1",
          kind: :message,
          payload: %{role: "user", content: "Hello!", sender_name: "Alice"}
        }
      ]

      result = UITurn.project_entries(entries)
      assert length(result) == 1
      assert hd(result).role == "user"
      assert hd(result).content == "Hello!"
      assert hd(result).sender_name == "Alice"
    end

    test "projects a single assistant turn" do
      entries = [
        %{
          id: "msg-2",
          kind: :ai_message,
          payload: %{
            role: "assistant",
            content: "Hi there!",
            sender_name: "Bot",
            request_id: "req-1"
          }
        }
      ]

      result = UITurn.project_entries(entries)
      assert length(result) == 1
      msg = hd(result)
      assert msg.role == "assistant"
      assert msg.content == "Hi there!"
      assert msg.sender_name == "Bot"
    end

    test "groups assistant entries with same request_id" do
      entries = [
        %{
          id: "msg-3",
          kind: :ai_message,
          payload: %{
            role: "assistant",
            content: "",
            thinking: "Let me think...",
            tool_calls: [],
            request_id: "req-2"
          }
        },
        %{
          id: "msg-4",
          kind: :ai_message,
          payload: %{
            role: "assistant",
            content: "Final answer",
            request_id: "req-2"
          }
        }
      ]

      result = UITurn.project_entries(entries)
      assert length(result) == 1
      msg = hd(result)
      assert msg.content == "Final answer"
      assert msg.thinking == "Let me think..."
    end

    test "includes tool call data in assistant turns" do
      tool_call = %{
        id: "tc-1",
        name: "search",
        arguments: %{query: "elixir"},
        result: nil
      }

      entries = [
        %{
          id: "msg-5",
          kind: :ai_message,
          payload: %{
            role: "assistant",
            content: "Found results",
            tool_calls: [tool_call],
            request_id: "req-3"
          }
        },
        %{
          id: "msg-6",
          kind: :ai_message,
          payload: %{
            role: "tool",
            tool_call_id: "tc-1",
            content: "Search results here",
            request_id: "req-3"
          }
        }
      ]

      result = UITurn.project_entries(entries)
      assert length(result) == 1
      msg = hd(result)
      assert length(msg.tool_calls) == 1
      tc = hd(msg.tool_calls)
      assert tc.name == "search"
      assert tc.result == "Search results here"
      assert tc.status == :completed
    end

    test "filters out irrelevant entries" do
      entries = [
        %{id: "msg-7", kind: :system, payload: %{content: "system msg"}},
        %{id: "msg-8", kind: :message, payload: %{role: "user", content: "Hello!"}}
      ]

      result = UITurn.project_entries(entries)
      assert length(result) == 1
      assert hd(result).content == "Hello!"
    end

    test "infers sender name from message prefix" do
      entries = [
        %{
          id: "msg-9",
          kind: :message,
          payload: %{role: "user", content: "[Bob]: Hi there!"}
        }
      ]

      result = UITurn.project_entries(entries)
      assert hd(result).sender_name == "Bob"
    end

    test "defaults sender name to You" do
      entries = [
        %{
          id: "msg-10",
          kind: :message,
          payload: %{role: "user", content: "Plain message"}
        }
      ]

      result = UITurn.project_entries(entries)
      assert hd(result).sender_name == "You"
    end
  end
end
