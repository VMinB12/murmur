defmodule JidoMurmur.Signals.MessageCompletedTest do
  use ExUnit.Case, async: true

  alias JidoMurmur.Signals.MessageCompleted

  describe "new/2" do
    test "creates signal with correct type and source" do
      {:ok, signal} =
        MessageCompleted.new(%{session_id: "sess_abc", response: "Hello!"})

      assert signal.type == "murmur.message.completed"
      assert signal.source == "/jido_murmur/runner"
      assert signal.data.session_id == "sess_abc"
      assert signal.data.response == "Hello!"
      assert signal.id != nil
      assert signal.time != nil
    end

    test "creates signal with subject override" do
      subject = MessageCompleted.subject("ws_1", "sess_abc")

      {:ok, signal} =
        MessageCompleted.new(
          %{session_id: "sess_abc", response: "Hi"},
          subject: subject
        )

      assert signal.subject == "/workspaces/ws_1/agents/sess_abc"
    end

    test "rejects missing session_id" do
      assert {:error, _} = MessageCompleted.new(%{response: "Hello!"})
    end

    test "rejects missing response" do
      assert {:error, _} = MessageCompleted.new(%{session_id: "sess_abc"})
    end

    test "rejects response payloads that are neither strings nor maps" do
      assert {:error, _} = MessageCompleted.new(%{session_id: "sess_abc", response: [:not, :valid]})
    end
  end

  describe "subject/2" do
    test "builds correct subject URI" do
      assert MessageCompleted.subject("ws_1", "sess_abc") ==
               "/workspaces/ws_1/agents/sess_abc"
    end
  end
end
