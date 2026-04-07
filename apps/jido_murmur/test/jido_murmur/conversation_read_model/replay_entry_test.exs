defmodule JidoMurmur.ConversationReadModel.ReplayEntryTest do
  use ExUnit.Case, async: true

  alias JidoMurmur.ActorIdentity
  alias JidoMurmur.ConversationReadModel.ReplayEntry

  describe "normalize/1" do
    test "normalizes string-keyed persisted entries into replay entry structs" do
      entry = %{
        "id" => "entry-1",
        "seq" => 4,
        "at" => 1_234,
        "kind" => "message",
        "payload" => %{
          "role" => "user",
          "content" => "hello",
          "sender_name" => "Alice"
        },
        "refs" => %{
          "origin_actor" => ActorIdentity.agent("Alice"),
          "request_id" => "req-1"
        }
      }

      normalized = ReplayEntry.normalize(entry)

      assert normalized.id == "entry-1"
      assert normalized.seq == 4
      assert normalized.at == 1_234
      assert normalized.kind == :message
      assert normalized.payload == %{role: "user", content: "hello", sender_name: "Alice"}
      assert normalized.refs == %{origin_actor: ActorIdentity.agent("Alice"), request_id: "req-1"}
      assert ReplayEntry.user?(normalized)
      assert ReplayEntry.request_id(normalized) == "req-1"
    end

    test "normalizes persisted tool call field aliases into canonical replay tool calls" do
      entry = %{
        kind: :ai_message,
        payload: %{
          role: "assistant",
          tool_calls: [
            %{"id" => "call-1", "function_name" => "search", "arguments" => %{"query" => "elixir"}}
          ]
        },
        refs: %{}
      }

      normalized = ReplayEntry.normalize(entry)

      assert normalized.payload.tool_calls == [
               %{id: "call-1", name: "search", args: %{"query" => "elixir"}}
             ]
    end
  end
end
