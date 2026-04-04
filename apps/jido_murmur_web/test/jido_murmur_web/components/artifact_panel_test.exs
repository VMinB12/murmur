defmodule JidoMurmurWeb.Components.ArtifactPanelTestRenderer do
  use Phoenix.Component

  attr :name, :string, required: true
  attr :data, :any, required: true
  attr :session_id, :string, required: true
  attr :active?, :boolean, default: false

  def badge(assigns) do
    ~H"""
    <span id="custom-badge">Custom: {@name}</span>
    """
  end

  attr :name, :string, required: true
  attr :data, :any, required: true
  attr :session_id, :string, required: true

  def detail(assigns) do
    ~H"""
    <div id="custom-detail">{@data["summary"]}</div>
    """
  end
end

defmodule JidoMurmurWeb.Components.ArtifactPanelTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias JidoArtifacts.Envelope
  alias JidoMurmurWeb.Components.ArtifactPanel
  alias JidoMurmurWeb.Components.ArtifactPanel.Generic
  alias JidoMurmurWeb.Components.ArtifactPanelTestRenderer

  defp envelope(data, source \\ "agent-1", version \\ 1) do
    Envelope.new(data, version, source, ~U[2026-01-01 00:00:00Z])
  end

  describe "ArtifactPanel.artifact_panel/1" do
    test "renders empty state when no artifacts" do
      html =
        render_component(&ArtifactPanel.artifact_panel/1,
          artifacts: %{},
          active_artifact: nil,
          agent_sessions: []
        )

      assert html =~ "No artifacts yet"
      assert html =~ "Artifacts"
      assert html =~ "Tool results and data will appear here"
    end

    test "renders tabs for artifacts across sessions" do
      sessions = [
        %{id: "s1", display_name: "Bot A"},
        %{id: "s2", display_name: "Bot B"}
      ]

      artifacts = %{
        "s1" => %{"papers" => envelope([%{"title" => "Paper 1"}])},
        "s2" => %{"tasks" => envelope([%{"title" => "Task 1"}], "agent-2")}
      }

      html =
        render_component(&ArtifactPanel.artifact_panel/1,
          artifacts: artifacts,
          active_artifact: nil,
          agent_sessions: sessions
        )

      assert html =~ "Bot A"
      assert html =~ "papers"
      assert html =~ "Bot B"
      assert html =~ "tasks"
    end

    test "highlights active artifact tab" do
      sessions = [%{id: "s1", display_name: "Bot A"}]
      artifacts = %{"s1" => %{"papers" => envelope([%{"title" => "P1"}])}}
      active = %{session_id: "s1", name: "papers"}

      html =
        render_component(&ArtifactPanel.artifact_panel/1,
          artifacts: artifacts,
          active_artifact: active,
          agent_sessions: sessions
        )

      assert html =~ "bg-primary/15"
    end

    test "renders detail view for active artifact" do
      sessions = [%{id: "s1", display_name: "Bot A"}]

      artifacts = %{
        "s1" => %{
          "insight" => envelope(%{"summary" => "Deep Learning Paper"})
        }
      }

      active = %{session_id: "s1", name: "insight"}

      html =
        render_component(&ArtifactPanel.artifact_panel/1,
          artifacts: artifacts,
          active_artifact: active,
          agent_sessions: sessions,
          renderers: %{"insight" => ArtifactPanelTestRenderer}
        )

      assert html =~ "Deep Learning Paper"
      assert html =~ "custom-detail"
    end

    test "skips empty artifacts in tabs" do
      sessions = [%{id: "s1", display_name: "Bot"}]

      artifacts = %{
        "s1" => %{
          "empty_list" => envelope([]),
          "empty_map" => envelope(%{}),
          "valid" => envelope(["data"])
        }
      }

      html =
        render_component(&ArtifactPanel.artifact_panel/1,
          artifacts: artifacts,
          active_artifact: nil,
          agent_sessions: sessions
        )

      assert html =~ "valid"
      refute html =~ "empty_list"
      refute html =~ "empty_map"
    end
  end

  describe "ArtifactPanel.artifact_badge/1" do
    test "falls back to Generic when no renderer is registered" do
      html =
        render_component(&ArtifactPanel.artifact_badge/1,
          name: "papers",
          data: envelope([%{"title" => "P1"}, %{"title" => "P2"}]),
          session_id: "s1"
        )

      assert html =~ "papers"
      assert html =~ "(2)"
    end

    test "dispatches to Generic for unknown types" do
      html =
        render_component(&ArtifactPanel.artifact_badge/1,
          name: "custom_data",
          data: envelope(["item1", "item2", "item3"]),
          session_id: "s1"
        )

      assert html =~ "custom_data"
      assert html =~ "(3)"
    end

    test "dispatches to custom renderer when provided" do
      html =
        render_component(&ArtifactPanel.artifact_badge/1,
          name: "my_type",
          data: envelope("test"),
          session_id: "s1",
          renderers: %{"my_type" => ArtifactPanelTestRenderer}
        )

      assert html =~ "custom-badge"
      assert html =~ "Custom: my_type"
    end
  end

  describe "Generic renderer" do
    test "renders badge with count for lists" do
      html =
        render_component(&Generic.badge/1,
          name: "results",
          data: [1, 2, 3],
          session_id: "s1"
        )

      assert html =~ "results (3)"
    end

    test "renders badge without count for non-lists" do
      html =
        render_component(&Generic.badge/1,
          name: "info",
          data: %{key: "val"},
          session_id: "s1"
        )

      assert html =~ "info"
      refute html =~ "("
    end

    test "renders detail for list data" do
      html =
        render_component(&Generic.detail/1,
          name: "items",
          data: ["alpha", "beta", "gamma"],
          session_id: "s1"
        )

      assert html =~ "items"
      assert html =~ "3 items"
      assert html =~ "alpha"
      assert html =~ "beta"
      assert html =~ "gamma"
    end

    test "renders detail for map data" do
      html =
        render_component(&Generic.detail/1,
          name: "config",
          data: %{key: "val"},
          session_id: "s1"
        )

      assert html =~ "config"
    end

    test "highlights active badge" do
      html =
        render_component(&Generic.badge/1,
          name: "data",
          data: "test",
          session_id: "s1",
          active?: true
        )

      assert html =~ "bg-primary/20"
      assert html =~ "ring-1"
    end
  end

end
