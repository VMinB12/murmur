defmodule JidoMurmur.WorkspaceContextTest do
  use ExUnit.Case, async: true

  alias JidoMurmur.StreamingPlugin

  describe "workspace_id extraction from agent state" do
    test "stream_topic/2 includes workspace_id" do
      assert StreamingPlugin.stream_topic("ws-123", "sess-456") ==
               "workspace:ws-123:agent:sess-456:stream"
    end
  end
end
