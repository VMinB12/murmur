defmodule JidoMurmur.Ingress.MetadataTest do
  use JidoMurmur.Case, async: true

  alias JidoMurmur.Ingress.Metadata

  describe "new/1" do
    test "projects canonical ingress metadata into a struct" do
      assert {:ok, metadata} =
               Metadata.new(%{
                 interaction_id: "i-1",
                 workspace_id: "w-1",
                 sender_name: "Alice",
                 sender_trace_id: "trace-1",
                 hop_count: 2,
                 request_origin: :tool
               })

      assert metadata.interaction_id == "i-1"
      assert metadata.workspace_id == "w-1"
      assert metadata.sender_name == "Alice"
      assert metadata.sender_trace_id == "trace-1"
      assert metadata.hop_count == 2
      assert metadata.extra == %{request_origin: :tool}
    end

    test "rejects non-atom metadata keys" do
      assert {:error, :invalid_refs} =
               Metadata.new(%{"interaction_id" => "i-1", workspace_id: "w-1"})
    end

    test "rejects invalid hop counts" do
      assert {:error, :invalid_hop_count} =
               Metadata.new(%{interaction_id: "i-1", workspace_id: "w-1", hop_count: -1})
    end
  end

  describe "tool_context/3" do
    test "projects runtime context from canonical metadata" do
      metadata = %Metadata{
        interaction_id: "i-1",
        workspace_id: "w-1",
        sender_name: "Alice",
        sender_trace_id: "trace-1",
        hop_count: 3,
        extra: %{}
      }

      tool_context = Metadata.tool_context(metadata, "Bob", "request-1")

      assert tool_context.workspace_id == "w-1"
      assert tool_context.sender_name == "Bob"
      assert tool_context.origin_sender_name == "Alice"
      assert tool_context.sender_trace_id == "trace-1"
      assert tool_context.interaction_id == "i-1"
      assert tool_context.request_id == "request-1"
      assert tool_context.hop_count == 3
    end
  end
end
