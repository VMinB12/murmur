defmodule JidoMurmur.Actions.StoreArtifactTest do
  use ExUnit.Case, async: true

  alias JidoMurmur.Actions.StoreArtifact

  describe "run/2 with :replace mode" do
    test "stores new artifact in empty state" do
      params = %{artifact_name: "papers", artifact_data: [%{title: "P1"}], artifact_mode: :replace}
      ctx = %{state: %{artifacts: %{}}}

      assert {:ok, %{artifacts: artifacts}} = StoreArtifact.run(params, ctx)
      assert artifacts == %{"papers" => [%{title: "P1"}]}
    end

    test "replaces existing artifact" do
      params = %{artifact_name: "papers", artifact_data: [%{title: "P2"}], artifact_mode: :replace}
      ctx = %{state: %{artifacts: %{"papers" => [%{title: "P1"}]}}}

      assert {:ok, %{artifacts: artifacts}} = StoreArtifact.run(params, ctx)
      assert artifacts == %{"papers" => [%{title: "P2"}]}
    end

    test "preserves other artifacts when replacing" do
      params = %{artifact_name: "docs", artifact_data: "new doc", artifact_mode: :replace}
      ctx = %{state: %{artifacts: %{"papers" => [1, 2], "docs" => "old doc"}}}

      assert {:ok, %{artifacts: artifacts}} = StoreArtifact.run(params, ctx)
      assert artifacts["papers"] == [1, 2]
      assert artifacts["docs"] == "new doc"
    end
  end

  describe "run/2 with :append mode" do
    test "appends to existing list artifact" do
      params = %{artifact_name: "papers", artifact_data: [%{id: 3}], artifact_mode: :append}
      ctx = %{state: %{artifacts: %{"papers" => [%{id: 1}, %{id: 2}]}}}

      assert {:ok, %{artifacts: artifacts}} = StoreArtifact.run(params, ctx)
      assert length(artifacts["papers"]) == 3
    end

    test "creates new list when appending to nonexistent artifact" do
      params = %{artifact_name: "results", artifact_data: %{q: "test"}, artifact_mode: :append}
      ctx = %{state: %{artifacts: %{}}}

      assert {:ok, %{artifacts: artifacts}} = StoreArtifact.run(params, ctx)
      assert artifacts["results"] == [%{q: "test"}]
    end

    test "wraps scalar data in list when appending" do
      params = %{artifact_name: "log", artifact_data: "entry1", artifact_mode: :append}
      ctx = %{state: %{artifacts: %{"log" => ["entry0"]}}}

      assert {:ok, %{artifacts: artifacts}} = StoreArtifact.run(params, ctx)
      assert artifacts["log"] == ["entry0", "entry1"]
    end
  end

  describe "run/2 with nil artifacts state" do
    test "handles nil artifacts gracefully" do
      params = %{artifact_name: "test", artifact_data: "data", artifact_mode: :replace}
      ctx = %{state: %{artifacts: nil}}

      assert {:ok, %{artifacts: artifacts}} = StoreArtifact.run(params, ctx)
      assert artifacts == %{"test" => "data"}
    end

    test "handles missing artifacts key" do
      params = %{artifact_name: "test", artifact_data: "data", artifact_mode: :replace}
      ctx = %{state: %{}}

      assert {:ok, %{artifacts: artifacts}} = StoreArtifact.run(params, ctx)
      assert artifacts == %{"test" => "data"}
    end
  end
end
