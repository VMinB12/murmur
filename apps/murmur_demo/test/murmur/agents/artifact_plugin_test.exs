defmodule Murmur.Agents.ArtifactPluginTest do
  @moduledoc """
  Tests for the ArtifactPlugin.

  Covers:
  - PubSub broadcast on artifact signal
  - Override routing to StoreArtifact action
  - Replace and append modes forwarded correctly
  """
  use Murmur.DataCase

  alias JidoArtifacts.Actions.StoreArtifact
  alias JidoArtifacts.Artifact
  alias JidoArtifacts.ArtifactPlugin

  @workspace_id "test-workspace-456"
  @session_id "test-session-123"

  setup do
    Phoenix.PubSub.subscribe(Murmur.PubSub, Artifact.artifact_topic(@workspace_id, @session_id))
    :ok
  end

  defp build_context do
    %{agent: %{id: @session_id, state: %{workspace_id: @workspace_id}}}
  end

  defp build_signal(name, data, mode) do
    Jido.Signal.new!(
      "artifact.#{name}",
      %{name: name, data: data, mode: mode},
      source: "/artifact/#{name}"
    )
  end

  describe "handle_signal/2" do
    test "broadcasts artifact signal via PubSub" do
      signal = build_signal("papers", [%{id: 1, title: "Test"}], :replace)

      ArtifactPlugin.handle_signal(signal, build_context())

      assert_receive %Jido.Signal{type: "artifact.papers", data: data}
      assert data[:name] == "papers" or data["name"] == "papers"
    end

    test "returns override to StoreArtifact action with replace mode" do
      signal = build_signal("papers", [%{id: 1}], :replace)

      assert {:ok, {:override, {StoreArtifact, params}}} =
               ArtifactPlugin.handle_signal(signal, build_context())

      assert params.artifact_name == "papers"
      assert params.artifact_data == [%{id: 1}]
      assert params.artifact_mode == :replace
    end

    test "returns override to StoreArtifact action with append mode" do
      signal = build_signal("papers", [%{id: 2}], :append)

      assert {:ok, {:override, {StoreArtifact, params}}} =
               ArtifactPlugin.handle_signal(signal, build_context())

      assert params.artifact_name == "papers"
      assert params.artifact_data == [%{id: 2}]
      assert params.artifact_mode == :append
    end

    test "defaults mode to :replace when not specified" do
      signal =
        Jido.Signal.new!(
          "artifact.doc",
          %{name: "doc", data: %{content: "hello"}},
          source: "/artifact/doc"
        )

      assert {:ok, {:override, {StoreArtifact, params}}} =
               ArtifactPlugin.handle_signal(signal, build_context())

      assert params.artifact_mode == :replace
    end

    test "handles string-keyed signal data" do
      signal =
        Jido.Signal.new!(
          "artifact.papers",
          %{"name" => "papers", "data" => [%{"id" => 1}], "mode" => :append},
          source: "/artifact/papers"
        )

      assert {:ok, {:override, {StoreArtifact, params}}} =
               ArtifactPlugin.handle_signal(signal, build_context())

      assert params.artifact_name == "papers"
      assert params.artifact_data == [%{"id" => 1}]
      assert params.artifact_mode == :append
    end
  end
end
