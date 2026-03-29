defmodule JidoMurmur.ArtifactPluginTest do
  use JidoMurmur.Case, async: true

  alias JidoMurmur.Artifact
  alias JidoMurmur.ArtifactPlugin

  describe "handle_signal/2" do
    test "broadcasts artifact update via PubSub" do
      session_id = Ecto.UUID.generate()
      topic = Artifact.artifact_topic(session_id)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), topic)

      signal = %{
        type: "artifact.papers",
        data: %{name: "papers", data: [%{title: "Paper 1"}], mode: :replace}
      }

      context = %{agent: %{id: session_id}}

      assert {:ok, {:override, {JidoMurmur.Actions.StoreArtifact, store_params}}} =
               ArtifactPlugin.handle_signal(signal, context)

      assert store_params.artifact_name == "papers"
      assert store_params.artifact_data == [%{title: "Paper 1"}]
      assert store_params.artifact_mode == :replace

      assert_receive {:artifact_update, ^session_id, "papers", [%{title: "Paper 1"}], :replace}
    end

    test "handles append mode" do
      session_id = Ecto.UUID.generate()
      topic = Artifact.artifact_topic(session_id)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), topic)

      signal = %{
        type: "artifact.results",
        data: %{name: "results", data: %{query: "test"}, mode: :append}
      }

      context = %{agent: %{id: session_id}}

      assert {:ok, {:override, {JidoMurmur.Actions.StoreArtifact, store_params}}} =
               ArtifactPlugin.handle_signal(signal, context)

      assert store_params.artifact_mode == :append

      assert_receive {:artifact_update, ^session_id, "results", %{query: "test"}, :append}
    end

    test "defaults mode to :replace when not specified" do
      session_id = Ecto.UUID.generate()
      topic = Artifact.artifact_topic(session_id)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), topic)

      signal = %{
        type: "artifact.doc",
        data: %{name: "doc", data: "some content"}
      }

      context = %{agent: %{id: session_id}}

      assert {:ok, {:override, {JidoMurmur.Actions.StoreArtifact, store_params}}} =
               ArtifactPlugin.handle_signal(signal, context)

      assert store_params.artifact_mode == :replace
    end

    test "handles string keys in data map" do
      session_id = Ecto.UUID.generate()
      topic = Artifact.artifact_topic(session_id)
      Phoenix.PubSub.subscribe(JidoMurmur.pubsub(), topic)

      signal = %{
        type: "artifact.search",
        data: %{"name" => "search", "data" => [1, 2, 3], "mode" => :append}
      }

      context = %{agent: %{id: session_id}}

      assert {:ok, {:override, {JidoMurmur.Actions.StoreArtifact, store_params}}} =
               ArtifactPlugin.handle_signal(signal, context)

      assert store_params.artifact_name == "search"
      assert store_params.artifact_data == [1, 2, 3]

      assert_receive {:artifact_update, ^session_id, "search", [1, 2, 3], :append}
    end
  end
end
