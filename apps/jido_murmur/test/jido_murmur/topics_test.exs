defmodule JidoMurmur.TopicsTest do
  use ExUnit.Case, async: true

  alias JidoMurmur.Topics

  describe "agent_artifacts/2" do
    test "returns workspace-scoped artifacts topic" do
      assert Topics.agent_artifacts("ws-1", "sess-1") == "workspace:ws-1:agent:sess-1:artifacts"
    end
  end

  describe "agent_stream/2" do
    test "returns workspace-scoped stream topic" do
      assert Topics.agent_stream("ws-1", "sess-1") == "workspace:ws-1:agent:sess-1:stream"
    end
  end

  describe "agent_messages/2" do
    test "returns workspace-scoped messages topic" do
      assert Topics.agent_messages("ws-1", "sess-1") == "workspace:ws-1:agent:sess-1:messages"
    end
  end

  describe "workspace_tasks/1" do
    test "returns workspace-scoped tasks topic" do
      assert Topics.workspace_tasks("ws-1") == "workspace:ws-1:tasks"
    end
  end

  describe "workspace/1" do
    test "returns workspace topic" do
      assert Topics.workspace("ws-1") == "workspace:ws-1"
    end
  end
end
