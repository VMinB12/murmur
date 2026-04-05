defmodule JidoMurmur.Signals.MessageReceivedTest do
  use ExUnit.Case, async: true

  alias JidoMurmur.Signals.MessageReceived

  test "validate_message accepts the full inter-agent payload" do
    payload = %{
      id: Uniq.UUID.uuid7(),
      role: "user",
      content: "[Alice]: hello",
      kind: :steering,
      sender_name: "Alice",
      sender_trace_id: nil
    }

    assert {:ok, ^payload} = MessageReceived.validate_message(payload)
  end

  test "validate_message rejects payloads missing ingress correlation fields" do
    payload = %{
      id: Uniq.UUID.uuid7(),
      role: "user",
      content: "hello"
    }

    assert {:error, message} = MessageReceived.validate_message(payload)
    assert message =~ "sender_name"
  end
end
