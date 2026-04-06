defmodule JidoMurmur.ConversationReadModel.EntryProjectorTest do
  use ExUnit.Case, async: true

  alias JidoMurmur.ActorIdentity
  alias JidoMurmur.ConversationReadModel
  alias JidoMurmur.ConversationReadModel.EntryProjector
  alias JidoMurmur.DisplayMessage.ToolCall

  describe "project_entries/2" do
    test "returns an empty model for empty entries" do
      assert %ConversationReadModel{messages: []} = EntryProjector.project_entries("session-1", [])
    end

    test "preserves explicit origin actor metadata for user messages" do
      entries = [
        %{
          id: "user-1",
          kind: :message,
          seq: 1,
          at: 1_000,
          payload: %{role: "user", content: "Hi there"},
          refs: %{origin_actor: ActorIdentity.agent("Bob")}
        }
      ]

      assert %ConversationReadModel{messages: [message]} = EntryProjector.project_entries("session-1", entries)
      assert message.role == "user"
      assert message.sender_name == "Bob"
      assert message.actor == ActorIdentity.agent("Bob")
      assert message.first_seen_seq == 1
    end

    test "reconstructs multiple assistant steps and nested tool results for one request" do
      entries = [
        %{
          id: "assistant-1",
          kind: :ai_message,
          seq: 1,
          at: 1_000,
          payload: %{
            role: "assistant",
            content: "Let me search",
            request_id: "req-1",
            tool_calls: [%{id: "call-1", name: "search", arguments: %{query: "elixir"}}]
          },
          refs: %{}
        },
        %{
          id: "tool-1",
          kind: :ai_message,
          seq: 2,
          at: 1_100,
          payload: %{role: "tool", content: "3 results", tool_call_id: "call-1", request_id: "req-1"},
          refs: %{}
        },
        %{
          id: "assistant-2",
          kind: :ai_message,
          seq: 3,
          at: 2_000,
          payload: %{role: "assistant", content: "Final answer", request_id: "req-1"},
          refs: %{}
        }
      ]

      assert %ConversationReadModel{messages: [step_one, step_two]} =
           EntryProjector.project_entries("session-1", entries)

      assert step_one.id == "req-1-step-1"
      assert step_one.step_index == 1
      assert step_one.status == :completed
      assert [%ToolCall{id: "call-1", name: "search", result: "3 results", status: :completed}] = step_one.tool_calls

      assert step_two.id == "req-1-step-2"
      assert step_two.step_index == 2
      assert step_two.content == "Final answer"
      assert step_two.tool_calls == []
      assert step_two.status == :completed
    end

    test "supports legacy kind message entries alongside assistant steps" do
      entries = [
        %{
          id: "legacy-user",
          kind: :message,
          seq: 1,
          at: 1_000,
          payload: %{role: "user", content: "Legacy", sender_name: "You"},
          refs: %{}
        },
        %{
          id: "assistant-1",
          kind: :ai_message,
          seq: 2,
          at: 2_000,
          payload: %{role: "assistant", content: "Reply", request_id: "req-2"},
          refs: %{}
        }
      ]

      assert %ConversationReadModel{messages: [user, assistant]} =
               EntryProjector.project_entries("session-1", entries)

      assert user.role == "user"
      assert user.content == "Legacy"
      assert user.sender_name == "You"
      assert assistant.id == "req-2-step-1"
      assert assistant.content == "Reply"
    end
  end
end
