defmodule JidoArtifacts.SignalPayloadTest do
  use ExUnit.Case, async: true

  alias JidoArtifacts.Envelope
  alias JidoArtifacts.SignalPayload
  alias JidoArtifacts.SignalUpdate

  describe "SignalPayload.new/3" do
    test "builds a replace payload" do
      assert {:ok, %SignalPayload{} = payload} = SignalPayload.new("papers", [%{id: 1}])

      assert payload.name == "papers"
      assert payload.payload == [%{id: 1}]
      assert payload.mode == :replace
      assert payload.scope == :agent
      assert is_nil(payload.merge_result)
    end

    test "builds a merge payload with explicit scope" do
      assert {:ok, %SignalPayload{} = payload} =
               SignalPayload.new("papers", [%{id: 2}],
                 mode: :merge,
                 merge_result: [%{id: 1}, %{id: 2}],
                 scope: :workspace
               )

      assert payload.mode == :merge
      assert payload.merge_result == [%{id: 1}, %{id: 2}]
      assert payload.scope == :workspace
    end

    test "rejects invalid mode" do
      assert {:error, _} = SignalPayload.new("papers", [], mode: :append)
    end
  end

  describe "SignalUpdate.new/3" do
    test "builds an update payload with envelope data" do
      envelope = Envelope.new([%{id: 1}], 1, "agent-1", ~U[2026-01-01 00:00:00Z])

      assert {:ok, %SignalUpdate{} = update} = SignalUpdate.new("papers", envelope, mode: :merge)

      assert update.name == "papers"
      assert update.envelope == envelope
      assert update.mode == :merge
      assert update.scope == :agent
    end

    test "accepts nil envelope for delete semantics" do
      assert {:ok, %SignalUpdate{} = update} = SignalUpdate.new("papers", nil)
      assert is_nil(update.envelope)
    end

    test "rejects non-envelope values" do
      assert {:error, _} = SignalUpdate.new("papers", [%{id: 1}])
    end
  end
end
