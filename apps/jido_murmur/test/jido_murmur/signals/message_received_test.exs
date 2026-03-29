defmodule JidoMurmur.Signals.MessageReceivedTest do
  use ExUnit.Case, async: true

  alias JidoMurmur.Signals.MessageReceived

  describe "new/2" do
    test "creates signal with correct type and source" do
      msg = %{role: "user", content: "Hello"}
      {:ok, signal} = MessageReceived.new(%{session_id: "sess_abc", message: msg})

      assert signal.type == "murmur.message.received"
      assert signal.source == "/jido_murmur/tell_action"
      assert signal.data.session_id == "sess_abc"
      assert signal.data.message == msg
      assert signal.id != nil
    end

    test "creates signal with subject override" do
      subject = MessageReceived.subject("ws_1", "sess_abc")
      msg = %{role: "user", content: "Hi"}

      {:ok, signal} =
        MessageReceived.new(%{session_id: "sess_abc", message: msg}, subject: subject)

      assert signal.subject == "/workspaces/ws_1/agents/sess_abc"
    end

    test "rejects missing session_id" do
      assert {:error, _} = MessageReceived.new(%{message: %{role: "user"}})
    end

    test "rejects missing message" do
      assert {:error, _} = MessageReceived.new(%{session_id: "sess_abc"})
    end
  end

  describe "subject/2" do
    test "builds correct subject URI" do
      assert MessageReceived.subject("ws_1", "sess_abc") ==
               "/workspaces/ws_1/agents/sess_abc"
    end
  end
end
