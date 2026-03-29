defmodule JidoMurmurWeb.Components.WorkspaceListTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias JidoMurmurWeb.Components.WorkspaceList

  describe "workspace_list/1" do
    test "renders empty state when no workspaces" do
      html = render_component(&WorkspaceList.workspace_list/1, workspaces: [])

      assert html =~ "No workspaces yet"
      assert html =~ "hero-folder-open"
    end

    test "renders workspace items" do
      workspaces = [
        %{id: "ws-1", name: "Research"},
        %{id: "ws-2", name: "Development"}
      ]

      html = render_component(&WorkspaceList.workspace_list/1, workspaces: workspaces)

      assert html =~ "Research"
      assert html =~ "Development"
      assert html =~ "hero-chat-bubble-left-right"
      assert html =~ "hero-chevron-right"
    end

    test "generates default href for each workspace" do
      workspaces = [%{id: "abc-123", name: "My Space"}]

      html = render_component(&WorkspaceList.workspace_list/1, workspaces: workspaces)

      assert html =~ "/workspaces/abc-123"
    end

    test "uses custom href_fn when provided" do
      workspaces = [%{id: "ws-1", name: "Custom"}]
      href_fn = fn ws -> "/custom/#{ws.id}" end

      html =
        render_component(&WorkspaceList.workspace_list/1,
          workspaces: workspaces,
          href_fn: href_fn
        )

      assert html =~ "/custom/ws-1"
    end

    test "renders navigation links" do
      workspaces = [%{id: "ws-1", name: "Workspace 1"}]

      html = render_component(&WorkspaceList.workspace_list/1, workspaces: workspaces)

      assert html =~ "data-phx-link=\"redirect\""
    end
  end
end
