defmodule JidoMurmur.ArtifactTest do
  use ExUnit.Case, async: true

  alias JidoMurmur.Artifact

  describe "emit/4" do
    test "creates an Emit directive with default :replace mode" do
      directive = Artifact.emit(%{}, "papers", [%{id: 1}])

      assert %Jido.Agent.Directive.Emit{signal: signal} = directive
      assert signal.type == "artifact.papers"
      assert signal.data.name == "papers"
      assert signal.data.data == [%{id: 1}]
      assert signal.data.mode == :replace
    end

    test "creates an Emit directive with :append mode" do
      directive = Artifact.emit(%{}, "results", %{q: "test"}, mode: :append)

      assert %Jido.Agent.Directive.Emit{signal: signal} = directive
      assert signal.type == "artifact.results"
      assert signal.data.mode == :append
    end

    test "signal source includes artifact name" do
      directive = Artifact.emit(%{}, "chart", %{x: 1})

      assert %Jido.Agent.Directive.Emit{signal: signal} = directive
      assert signal.source == "/artifact/chart"
    end

    test "supports arbitrary data types" do
      directive = Artifact.emit(%{}, "text", "plain string content")

      assert %Jido.Agent.Directive.Emit{signal: signal} = directive
      assert signal.data.data == "plain string content"
    end
  end

  describe "artifact_topic/1" do
    test "returns a scoped PubSub topic" do
      assert Artifact.artifact_topic("session-123") == "agent_artifacts:session-123"
    end

    test "handles UUID session IDs" do
      uuid = Ecto.UUID.generate()
      assert Artifact.artifact_topic(uuid) == "agent_artifacts:#{uuid}"
    end
  end
end
