defmodule MurmurWeb.WorkspaceLiveArtifactSignalTest do
  use MurmurWeb.ConnCase

  import Phoenix.LiveViewTest

  alias JidoArtifacts.Envelope
  alias JidoArtifacts.SignalUpdate
  alias JidoMurmur.Topics
  alias JidoMurmur.Workspaces

  defp envelope(data, source, version \\ 1) do
    Envelope.new(data, version, source, ~U[2026-01-01 00:00:00Z])
  end

  defp artifact_signal(session_id, name, envelope) do
    Jido.Signal.new!(
      "artifact.#{name}",
      SignalUpdate.new!(name, envelope),
      source: "/jido_artifacts/#{name}",
      subject: "/agents/#{session_id}"
    )
  end

  setup do
    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Artifact Signal Test"})

    {:ok, session} =
      Workspaces.create_agent_session(workspace.id, %{
        "agent_profile_id" => "arxiv_agent",
        "display_name" => "Scholar"
      })

    %{workspace: workspace, session: session}
  end

  describe "signal-driven artifact updates" do
    test "papers signal renders badge count and detail content", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      papers = [
        %{
          id: "2301.00001",
          title: "Attention Is All You Need",
          abstract: "We propose a transformer architecture.",
          url: "https://arxiv.org/abs/2301.00001",
          pdf_url: "https://arxiv.org/pdf/2301.00001"
        },
        %{
          id: "2301.00002",
          title: "BERT: Pre-training",
          abstract: "We introduce a bidirectional encoder.",
          url: "https://arxiv.org/abs/2301.00002",
          pdf_url: "https://arxiv.org/pdf/2301.00002"
        }
      ]

      Phoenix.PubSub.broadcast!(
        Murmur.PubSub,
        Topics.agent_artifacts(workspace.id, session.id),
        artifact_signal(session.id, "papers", envelope(papers, session.id))
      )

      assert has_element?(view, ~s|button[phx-value-name="papers"]|, "2 papers")

      html = render(view)
      assert html =~ "Attention Is All You Need"
      assert html =~ "BERT: Pre-training"
    end

    test "displayed_paper signal renders title badge and pdf detail", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      displayed_paper = %{
        id: "2301.07041",
        title: "Retrieval-Augmented Generation",
        pdf_url: "https://arxiv.org/pdf/2301.07041"
      }

      Phoenix.PubSub.broadcast!(
        Murmur.PubSub,
        Topics.agent_artifacts(workspace.id, session.id),
        artifact_signal(session.id, "displayed_paper", envelope(displayed_paper, session.id))
      )

      assert has_element?(view, ~s|button[phx-value-name="displayed_paper"]|, "Retrieval-Augmented Generation")

      html = render(view)
      assert html =~ "Retrieval-Augmented Generation"
      assert html =~ "2301.07041"
      assert html =~ "Open in new tab"
    end

    test "sql_results signal renders query count and labels", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      sql_results = [
        %{
          sql: "SELECT * FROM agents ORDER BY inserted_at DESC",
          label: "Recent agents",
          row_count: 2,
          column_count: 4
        },
        %{
          sql: "SELECT * FROM tasks WHERE status = 'todo'",
          label: "Task backlog",
          row_count: 5,
          column_count: 3
        }
      ]

      Phoenix.PubSub.broadcast!(
        Murmur.PubSub,
        Topics.agent_artifacts(workspace.id, session.id),
        artifact_signal(session.id, "sql_results", envelope(sql_results, session.id))
      )

      assert has_element?(view, ~s|button[phx-value-name="sql_results"]|, "2 queries")

      html = render(view)
      assert html =~ "Recent agents"
      assert html =~ "Task backlog"
      assert html =~ "2 rows"
      assert html =~ "5 rows"
    end
  end
end
