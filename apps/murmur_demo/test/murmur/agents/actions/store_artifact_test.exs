defmodule Murmur.Agents.Actions.StoreArtifactTest do
  @moduledoc """
  Tests for the StoreArtifact action.

  Covers:
  - Replace mode creates metadata envelope
  - Version increments on update
  - Works with empty initial state
  - Preserves other artifacts when updating one
  """
  use ExUnit.Case, async: true

  alias JidoArtifacts.Actions.StoreArtifact
  alias JidoArtifacts.Envelope

  defp envelope(data, source \\ "agent-1", version \\ 1) do
    Envelope.new(data, version, source, ~U[2026-01-01 00:00:00Z])
  end

  describe "run/2 with :replace mode" do
    test "stores artifact data in envelope when no prior artifacts exist" do
      ctx = %{state: %{}}
      params = %{artifact_name: "papers", artifact_data: [%{id: 1}], artifact_mode: :replace}

      assert {:ok, %{artifacts: artifacts}} = StoreArtifact.run(params, ctx)
      assert artifacts["papers"].data == [%{id: 1}]
      assert artifacts["papers"].version == 1
    end

    test "replaces existing artifact data with version increment" do
      existing = envelope([%{id: 1}])
      ctx = %{state: %{artifacts: %{"papers" => existing}}}
      params = %{artifact_name: "papers", artifact_data: [%{id: 2}], artifact_mode: :replace}

      assert {:ok, %{artifacts: artifacts}} = StoreArtifact.run(params, ctx)
      assert artifacts["papers"].data == [%{id: 2}]
      assert artifacts["papers"].version == 2
    end

    test "preserves other artifacts" do
      queries_envelope = envelope([%{sql: "SELECT 1"}], "a")
      ctx = %{state: %{artifacts: %{"queries" => queries_envelope}}}
      params = %{artifact_name: "papers", artifact_data: [%{id: 2}], artifact_mode: :replace}

      {:ok, %{artifacts: updated}} = StoreArtifact.run(params, ctx)

      assert updated["papers"].data == [%{id: 2}]
      assert updated["queries"] == queries_envelope
    end

    test "replaces with a map value (non-list)" do
      ctx = %{state: %{}}
      params = %{artifact_name: "displayed_paper", artifact_data: %{id: "123", title: "A Paper"}, artifact_mode: :replace}

      {:ok, %{artifacts: updated}} = StoreArtifact.run(params, ctx)

      assert updated["displayed_paper"].data == %{id: "123", title: "A Paper"}
    end
  end

  describe "run/2 with :merge mode" do
    test "stores merge_result in envelope" do
      ctx = %{state: %{}}

      params = %{
        artifact_name: "papers",
        artifact_data: [%{id: 1}],
        artifact_mode: :merge,
        merge_result: [%{id: 1}]
      }

      assert {:ok, %{artifacts: artifacts}} = StoreArtifact.run(params, ctx)
      assert artifacts["papers"].data == [%{id: 1}]
    end

    test "deletes key when merge_result is nil" do
      existing = envelope([%{id: 1}], "a")
      ctx = %{state: %{artifacts: %{"papers" => existing}}}

      params = %{
        artifact_name: "papers",
        artifact_data: nil,
        artifact_mode: :merge,
        merge_result: nil
      }

      assert {:ok, %{artifacts: artifacts}} = StoreArtifact.run(params, ctx)
      refute Map.has_key?(artifacts, "papers")
    end
  end
end
