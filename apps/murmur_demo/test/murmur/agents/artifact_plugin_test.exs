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
  alias JidoArtifacts.Envelope
  alias JidoArtifacts.SignalPayload
  alias JidoArtifacts.SignalUpdate

  @workspace_id "test-workspace-456"
  @session_id "test-session-123"

  setup do
    Phoenix.PubSub.subscribe(Murmur.PubSub, Artifact.artifact_topic(@workspace_id, @session_id))
    :ok
  end

  defp build_context(artifacts \\ %{}) do
    %{agent: %{id: @session_id, state: %{workspace_id: @workspace_id, artifacts: artifacts}}}
  end

  defp build_signal(name, data, mode) do
    Jido.Signal.new!(
      "artifact.#{name}",
      SignalPayload.new!(name, data, mode: mode),
      source: "/artifact/#{name}"
    )
  end

  describe "handle_signal/2" do
    test "broadcasts artifact signal via PubSub" do
      signal = build_signal("papers", [%{id: 1, title: "Test"}], :replace)

      ArtifactPlugin.handle_signal(signal, build_context())

      assert_receive %Jido.Signal{type: "artifact.papers", data: data}
      assert %SignalUpdate{name: "papers", envelope: %Envelope{}} = data
    end

    test "returns override to StoreArtifact action with replace mode" do
      signal = build_signal("papers", [%{id: 1}], :replace)

      assert {:ok, {:override, {StoreArtifact, params}}} =
               ArtifactPlugin.handle_signal(signal, build_context())

      assert params.artifact_name == "papers"
      assert params.artifact_data == [%{id: 1}]
      assert params.artifact_mode == :replace
      assert %Envelope{} = params.artifact_envelope
    end

    test "returns override to StoreArtifact action with merge mode" do
      signal =
        Jido.Signal.new!(
          "artifact.papers",
          SignalPayload.new!("papers", [%{id: 2}], mode: :merge, merge_result: [%{id: 2}]),
          source: "/artifact/papers"
        )

      assert {:ok, {:override, {StoreArtifact, params}}} =
               ArtifactPlugin.handle_signal(signal, build_context())

      assert params.artifact_name == "papers"
      assert params.artifact_data == [%{id: 2}]
      assert params.artifact_mode == :merge
      assert %Envelope{} = params.artifact_envelope
    end

    test "defaults mode to :replace when not specified" do
      signal =
        Jido.Signal.new!(
          "artifact.doc",
          SignalPayload.new!("doc", %{content: "hello"}),
          source: "/artifact/doc"
        )

      assert {:ok, {:override, {StoreArtifact, params}}} =
               ArtifactPlugin.handle_signal(signal, build_context())

      assert params.artifact_mode == :replace
    end

    test "computes merged envelope version from an existing artifact envelope" do
      existing_envelope = Envelope.new([%{id: 1}], 2, @session_id, ~U[2026-01-01 00:00:00Z])

      signal =
        Jido.Signal.new!(
          "artifact.papers",
          SignalPayload.new!("papers", [%{id: 2}],
            mode: :merge,
            merge_result: [%{id: 1}, %{id: 2}]
          ),
          source: "/artifact/papers"
        )

      assert {:ok, {:override, {StoreArtifact, params}}} =
               ArtifactPlugin.handle_signal(signal, build_context(%{"papers" => existing_envelope}))

      assert params.artifact_mode == :merge
      assert params.merge_result == [%{id: 1}, %{id: 2}]
      assert %Envelope{} = params.artifact_envelope
      assert params.artifact_envelope.data == [%{id: 1}, %{id: 2}]
      assert params.artifact_envelope.version == 3
      assert params.artifact_envelope.source == @session_id
    end
  end
end
