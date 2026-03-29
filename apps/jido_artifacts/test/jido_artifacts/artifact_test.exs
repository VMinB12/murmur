defmodule JidoArtifacts.ArtifactTest do
  use ExUnit.Case, async: true

  alias JidoArtifacts.Artifact
  alias JidoArtifacts.Merge

  describe "emit/4 without merge (replace)" do
    test "creates an Emit directive with mode :replace" do
      directive = Artifact.emit(%{}, "papers", [%{id: 1}])

      assert %Jido.Agent.Directive.Emit{signal: signal} = directive
      assert signal.type == "artifact.papers"
      assert signal.data.name == "papers"
      assert signal.data.data == [%{id: 1}]
      assert signal.data.mode == :replace
      refute Map.has_key?(signal.data, :merge_result)
    end

    test "sets source to /jido_artifacts/<name>" do
      directive = Artifact.emit(%{}, "chart", %{x: 1})

      assert %Jido.Agent.Directive.Emit{signal: signal} = directive
      assert signal.source == "/jido_artifacts/chart"
    end

    test "supports arbitrary data types" do
      directive = Artifact.emit(%{}, "text", "plain string content")

      assert %Jido.Agent.Directive.Emit{signal: signal} = directive
      assert signal.data.data == "plain string content"
    end
  end

  describe "emit/4 with merge callback" do
    test "applies merge function and includes merge_result" do
      ctx = %{state: %{artifacts: %{"papers" => [%{id: 1}]}}}

      directive = Artifact.emit(ctx, "papers", [%{id: 2}], merge: &Merge.append/2)

      assert %Jido.Agent.Directive.Emit{signal: signal} = directive
      assert signal.data.mode == :merge
      assert signal.data.merge_result == [%{id: 1}, %{id: 2}]
      assert signal.data.data == [%{id: 2}]
    end

    test "handles nil existing via merge function" do
      ctx = %{state: %{artifacts: %{}}}

      directive = Artifact.emit(ctx, "papers", [%{id: 1}], merge: &Merge.append/2)

      assert %Jido.Agent.Directive.Emit{signal: signal} = directive
      assert signal.data.merge_result == [%{id: 1}]
    end

    test "works with append_max" do
      ctx = %{state: %{artifacts: %{"items" => [1, 2, 3]}}}

      directive = Artifact.emit(ctx, "items", [4, 5], merge: Merge.append_max(3))

      assert %Jido.Agent.Directive.Emit{signal: signal} = directive
      assert signal.data.merge_result == [3, 4, 5]
    end

    test "works with custom merge function" do
      ctx = %{state: %{artifacts: %{"count" => 5}}}

      merge = fn existing, new -> (existing || 0) + new end
      directive = Artifact.emit(ctx, "count", 3, merge: merge)

      assert %Jido.Agent.Directive.Emit{signal: signal} = directive
      assert signal.data.merge_result == 8
    end
  end

  describe "emit/4 CloudEvents fields" do
    test "sets source to /jido_artifacts/<name>" do
      directive = Artifact.emit(%{}, "papers", [])

      assert %Jido.Agent.Directive.Emit{signal: signal} = directive
      assert signal.source == "/jido_artifacts/papers"
    end

    test "sets subject to /agents/<agent_id> when present" do
      ctx = %{state: %{__agent_id__: "agent-123"}}

      directive = Artifact.emit(ctx, "papers", [])

      assert %Jido.Agent.Directive.Emit{signal: signal} = directive
      assert signal.subject == "/agents/agent-123"
    end

    test "subject is nil when no agent identity" do
      ctx = %{state: %{}}

      directive = Artifact.emit(ctx, "papers", [])

      assert %Jido.Agent.Directive.Emit{signal: signal} = directive
      assert is_nil(signal.subject)
    end
  end

  describe "emit/4 with scope" do
    test "default scope is :agent" do
      directive = Artifact.emit(%{}, "papers", [])

      assert %Jido.Agent.Directive.Emit{signal: signal} = directive
      assert signal.data.scope == :agent
    end

    test "explicit scope: :agent works" do
      directive = Artifact.emit(%{}, "papers", [], scope: :agent)

      assert %Jido.Agent.Directive.Emit{signal: signal} = directive
      assert signal.data.scope == :agent
    end

    test "scope: :workspace accepted in signal data" do
      directive = Artifact.emit(%{}, "papers", [], scope: :workspace)

      assert %Jido.Agent.Directive.Emit{signal: signal} = directive
      assert signal.data.scope == :workspace
    end
  end

  describe "artifact_topic/1" do
    test "returns a scoped PubSub topic" do
      assert Artifact.artifact_topic("session-123") == "jido_artifacts:session-123"
    end
  end
end
