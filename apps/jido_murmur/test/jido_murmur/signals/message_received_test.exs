defmodule JidoMurmur.Signals.MessageReceivedTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.ID, as: SignalID
  alias JidoMurmur.Signals.MessageReceived

  test "validate_message accepts the full inter-agent payload" do
    message_id = Uniq.UUID.uuid7()

    payload = %{
      id: message_id,
      role: "user",
      content: "[Alice]: hello",
      kind: :steering,
      sender_name: "Alice",
      first_seen_at: SignalID.extract_timestamp(message_id),
      first_seen_seq: SignalID.sequence_number(message_id),
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
