defmodule MurmurWeb.WorkspaceListLiveTest do
  @moduledoc """
  LiveView tests for the workspace list / home page.

  Covers:
  - FR-002: Users MUST be able to create a workspace
  - Edge: Empty state UI with guidance
  """
  use MurmurWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Murmur.Workspaces

  describe "mount" do
    test "renders empty state when no workspaces exist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/workspaces")
      assert has_element?(view, "h2", "No workspaces yet")
    end

    test "renders existing workspaces", %{conn: conn} do
      {:ok, _} = Workspaces.create_workspace(%{"name" => "My Team"})
      {:ok, view, _html} = live(conn, ~p"/workspaces")
      assert has_element?(view, "h3", "My Team")
    end
  end

  describe "create_workspace" do
    test "creates a workspace and navigates to it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/workspaces")

      view
      |> form("#create-workspace-form", workspace: %{name: "My Team"})
      |> render_submit()

      # Should navigate to the new workspace
      {path, _flash} = assert_redirect(view)
      assert path =~ "/workspaces/"
    end

    test "shows error for blank workspace name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/workspaces")

      html =
        view
        |> form("#create-workspace-form", workspace: %{name: ""})
        |> render_submit()

      assert html =~ "can" or has_element?(view, ".phx-form-error")
    end
  end

  describe "navigation" do
    test "clicking a workspace navigates to workspace page", %{conn: conn} do
      {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Test"})
      {:ok, view, _html} = live(conn, ~p"/workspaces")

      view
      |> element("a[href*='#{workspace.id}']")
      |> render_click()

      assert_redirect(view, ~p"/workspaces/#{workspace.id}")
    end
  end
end
