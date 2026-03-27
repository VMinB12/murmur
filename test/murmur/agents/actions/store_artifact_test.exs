defmodule Murmur.Agents.Actions.StoreArtifactTest do
  @moduledoc """
  Tests for the StoreArtifact action.

  Covers:
  - Replace mode overwrites artifact data
  - Append mode concatenates to existing list
  - Works with empty initial state
  - Preserves other artifacts when updating one
  """
  use ExUnit.Case, async: true

  alias Murmur.Agents.Actions.StoreArtifact

  describe "run/2 with :replace mode" do
    test "stores artifact data when no prior artifacts exist" do
      ctx = %{state: %{}}
      params = %{artifact_name: "papers", artifact_data: [%{id: 1}], artifact_mode: :replace}

      assert {:ok, %{artifacts: %{"papers" => [%{id: 1}]}}} = StoreArtifact.run(params, ctx)
    end

    test "replaces existing artifact data" do
      ctx = %{state: %{artifacts: %{"papers" => [%{id: 1}]}}}
      params = %{artifact_name: "papers", artifact_data: [%{id: 2}], artifact_mode: :replace}

      assert {:ok, %{artifacts: %{"papers" => [%{id: 2}]}}} = StoreArtifact.run(params, ctx)
    end

    test "preserves other artifacts" do
      ctx = %{state: %{artifacts: %{"papers" => [%{id: 1}], "queries" => [%{sql: "SELECT 1"}]}}}
      params = %{artifact_name: "papers", artifact_data: [%{id: 2}], artifact_mode: :replace}

      {:ok, %{artifacts: updated}} = StoreArtifact.run(params, ctx)

      assert updated["papers"] == [%{id: 2}]
      assert updated["queries"] == [%{sql: "SELECT 1"}]
    end

    test "replaces with a map value (non-list)" do
      ctx = %{state: %{}}
      params = %{artifact_name: "displayed_paper", artifact_data: %{id: "123", title: "A Paper"}, artifact_mode: :replace}

      {:ok, %{artifacts: updated}} = StoreArtifact.run(params, ctx)

      assert updated["displayed_paper"] == %{id: "123", title: "A Paper"}
    end
  end

  describe "run/2 with :append mode" do
    test "appends to empty artifact" do
      ctx = %{state: %{}}
      params = %{artifact_name: "papers", artifact_data: [%{id: 1}], artifact_mode: :append}

      assert {:ok, %{artifacts: %{"papers" => [%{id: 1}]}}} = StoreArtifact.run(params, ctx)
    end

    test "appends to existing list" do
      ctx = %{state: %{artifacts: %{"papers" => [%{id: 1}]}}}
      params = %{artifact_name: "papers", artifact_data: [%{id: 2}], artifact_mode: :append}

      {:ok, %{artifacts: updated}} = StoreArtifact.run(params, ctx)

      assert updated["papers"] == [%{id: 1}, %{id: 2}]
    end

    test "wraps non-list data in a list for append" do
      ctx = %{state: %{artifacts: %{"papers" => [%{id: 1}]}}}
      params = %{artifact_name: "papers", artifact_data: %{id: 2}, artifact_mode: :append}

      {:ok, %{artifacts: updated}} = StoreArtifact.run(params, ctx)

      assert updated["papers"] == [%{id: 1}, %{id: 2}]
    end

    test "preserves other artifacts" do
      ctx = %{state: %{artifacts: %{"papers" => [%{id: 1}], "queries" => [%{sql: "SELECT 1"}]}}}
      params = %{artifact_name: "papers", artifact_data: [%{id: 2}], artifact_mode: :append}

      {:ok, %{artifacts: updated}} = StoreArtifact.run(params, ctx)

      assert updated["papers"] == [%{id: 1}, %{id: 2}]
      assert updated["queries"] == [%{sql: "SELECT 1"}]
    end
  end
end
