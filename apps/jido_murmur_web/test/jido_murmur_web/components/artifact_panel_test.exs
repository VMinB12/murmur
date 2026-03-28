defmodule JidoMurmurWeb.Components.ArtifactPanelTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias JidoMurmurWeb.Components.ArtifactPanel
  alias JidoMurmurWeb.Components.ArtifactPanel.Generic
  alias JidoMurmurWeb.Components.ArtifactPanel.PaperList
  alias JidoMurmurWeb.Components.ArtifactPanel.PdfViewer

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
        "s1" => %{"papers" => [%{"title" => "Paper 1"}]},
        "s2" => %{"tasks" => [%{"title" => "Task 1"}]}
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
      artifacts = %{"s1" => %{"papers" => [%{"title" => "P1"}]}}
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
          "papers" => [
            %{"title" => "Deep Learning Paper", "id" => "2301.00001", "abstract" => "Abstract text"}
          ]
        }
      }

      active = %{session_id: "s1", name: "papers"}

      html =
        render_component(&ArtifactPanel.artifact_panel/1,
          artifacts: artifacts,
          active_artifact: active,
          agent_sessions: sessions
        )

      assert html =~ "Deep Learning Paper"
      assert html =~ "2301.00001"
    end

    test "skips empty artifacts in tabs" do
      sessions = [%{id: "s1", display_name: "Bot"}]
      artifacts = %{"s1" => %{"empty_list" => [], "empty_map" => %{}, "valid" => ["data"]}}

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
    test "dispatches to PaperList for papers" do
      html =
        render_component(&ArtifactPanel.artifact_badge/1,
          name: "papers",
          data: [%{"title" => "P1"}, %{"title" => "P2"}],
          session_id: "s1"
        )

      assert html =~ "2 papers"
      assert html =~ "hero-academic-cap"
    end

    test "dispatches to PdfViewer for displayed_paper" do
      html =
        render_component(&ArtifactPanel.artifact_badge/1,
          name: "displayed_paper",
          data: %{"title" => "My Paper", "id" => "2301.00001"},
          session_id: "s1"
        )

      assert html =~ "My Paper"
      assert html =~ "hero-document"
    end

    test "dispatches to Generic for unknown types" do
      html =
        render_component(&ArtifactPanel.artifact_badge/1,
          name: "custom_data",
          data: ["item1", "item2", "item3"],
          session_id: "s1"
        )

      assert html =~ "custom_data"
      assert html =~ "(3)"
    end

    test "dispatches to custom renderer when provided" do
      defmodule TestRenderer do
        use Phoenix.Component

        attr :name, :string, required: true
        attr :data, :any, required: true
        attr :session_id, :string, required: true
        attr :active?, :boolean, default: false
        attr :renderers, :map, default: %{}

        def badge(assigns) do
          ~H"""
          <span id="custom-badge">Custom: {@name}</span>
          """
        end
      end

      html =
        render_component(&ArtifactPanel.artifact_badge/1,
          name: "my_type",
          data: "test",
          session_id: "s1",
          renderers: %{"my_type" => TestRenderer}
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

  describe "PaperList renderer" do
    test "renders badge with paper count" do
      papers = [
        %{"title" => "Paper 1", "id" => "2301.00001"},
        %{"title" => "Paper 2", "id" => "2301.00002"}
      ]

      html = render_component(&PaperList.badge/1, data: papers, session_id: "s1")

      assert html =~ "2 papers"
      assert html =~ "hero-academic-cap"
    end

    test "renders detail with paper information" do
      papers = [
        %{
          "title" => "Attention Is All You Need",
          "id" => "1706.03762",
          "abstract" => "The dominant sequence transduction models...",
          "published" => "2017-06-12T00:00:00Z",
          "url" => "https://arxiv.org/abs/1706.03762",
          "pdf_url" => "https://arxiv.org/pdf/1706.03762"
        }
      ]

      html = render_component(&PaperList.detail/1, data: papers, session_id: "s1")

      assert html =~ "Attention Is All You Need"
      assert html =~ "1706.03762"
      assert html =~ "2017-06-12"
      assert html =~ "The dominant sequence transduction models..."
      assert html =~ "1 papers found"
    end
  end

  describe "PdfViewer renderer" do
    test "renders badge with paper title" do
      data = %{"title" => "My Wonderful Paper", "id" => "2301.00001", "pdf_url" => "https://example.com/paper.pdf"}

      html = render_component(&PdfViewer.badge/1, data: data, session_id: "s1")

      assert html =~ "My Wonderful Paper"
      assert html =~ "hero-document"
    end

    test "renders detail with iframe" do
      data = %{
        "title" => "My Paper",
        "id" => "2301.00001",
        "pdf_url" => "https://arxiv.org/pdf/2301.00001"
      }

      html = render_component(&PdfViewer.detail/1, data: data, session_id: "s1")

      assert html =~ "My Paper"
      assert html =~ "2301.00001"
      assert html =~ "<iframe"
      assert html =~ "https://arxiv.org/pdf/2301.00001"
      assert html =~ "Open in new tab"
    end
  end
end
