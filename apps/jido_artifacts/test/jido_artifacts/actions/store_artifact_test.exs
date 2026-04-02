defmodule JidoArtifacts.Actions.StoreArtifactTest do
  use ExUnit.Case, async: true

  alias JidoArtifacts.Actions.StoreArtifact
  alias JidoArtifacts.Envelope

  defp envelope(data, version \\ 1) do
    Envelope.new(data, version, "agent-1", ~U[2026-01-01 00:00:00Z])
  end

  describe "run/2 create (version 1)" do
    test "wraps new artifact in metadata envelope" do
      params = %{artifact_name: "papers", artifact_data: [%{id: 1}], artifact_mode: :replace}
      ctx = %{state: %{artifacts: %{}, __agent_id__: "agent-1"}}

      assert {:ok, %{artifacts: artifacts}} = StoreArtifact.run(params, ctx)

      envelope = artifacts["papers"]
      assert envelope.data == [%{id: 1}]
      assert envelope.version == 1
      assert envelope.source == "agent-1"
      assert %DateTime{} = envelope.updated_at
    end

    test "handles nil artifacts state" do
      params = %{artifact_name: "doc", artifact_data: "hello", artifact_mode: :replace}
      ctx = %{state: %{}}

      assert {:ok, %{artifacts: artifacts}} = StoreArtifact.run(params, ctx)

      envelope = artifacts["doc"]
      assert envelope.data == "hello"
      assert envelope.version == 1
    end
  end

  describe "run/2 update (version increment)" do
    test "increments version on update" do
      existing_envelope = envelope([%{id: 1}], 3)
      params = %{artifact_name: "papers", artifact_data: [%{id: 2}], artifact_mode: :replace}
      ctx = %{state: %{artifacts: %{"papers" => existing_envelope}, __agent_id__: "agent-1"}}

      assert {:ok, %{artifacts: artifacts}} = StoreArtifact.run(params, ctx)

      envelope = artifacts["papers"]
      assert envelope.data == [%{id: 2}]
      assert envelope.version == 4
    end

    test "preserves other artifacts" do
      other_envelope = envelope("other")
      params = %{artifact_name: "new", artifact_data: "data", artifact_mode: :replace}
      ctx = %{state: %{artifacts: %{"existing" => other_envelope}, __agent_id__: "agent-1"}}

      assert {:ok, %{artifacts: artifacts}} = StoreArtifact.run(params, ctx)

      assert artifacts["existing"] == other_envelope
      assert artifacts["new"].data == "data"
    end
  end

  describe "run/2 with merge_result" do
    test "stores merge_result data instead of raw data" do
      params = %{
        artifact_name: "papers",
        artifact_data: [%{id: 1}, %{id: 2}],
        artifact_mode: :merge,
        merge_result: [%{id: 1}, %{id: 2}]
      }

      ctx = %{state: %{artifacts: %{}, __agent_id__: "agent-1"}}

      assert {:ok, %{artifacts: artifacts}} = StoreArtifact.run(params, ctx)

      envelope = artifacts["papers"]
      assert envelope.data == [%{id: 1}, %{id: 2}]
    end
  end

  describe "run/2 delete (nil merge_result)" do
    test "removes key when merge_result is nil" do
      existing_envelope = envelope([%{id: 1}])

      params = %{
        artifact_name: "papers",
        artifact_data: nil,
        artifact_mode: :merge,
        merge_result: nil
      }

      ctx = %{state: %{artifacts: %{"papers" => existing_envelope}, __agent_id__: "agent-1"}}

      assert {:ok, %{artifacts: artifacts}} = StoreArtifact.run(params, ctx)

      refute Map.has_key?(artifacts, "papers")
    end
  end
end
