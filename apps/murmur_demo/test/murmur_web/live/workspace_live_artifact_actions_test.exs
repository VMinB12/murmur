defmodule MurmurWeb.WorkspaceLiveArtifactActionsTest do
  use MurmurWeb.ConnCase

  import Phoenix.LiveViewTest

  alias JidoArtifacts.Envelope
  alias JidoArtifacts.SignalUpdate
  alias JidoMurmur.Topics
  alias JidoMurmur.Workspaces
  alias JidoSql.QueryResult

  defmodule TestQueryExecutor do
    def execute(_repo, "BROKEN"), do: {:error, "boom"}

    def execute(_repo, _sql) do
      {:ok, QueryResult.new(["name", "role"], [["Neo", "agent"]], 1)}
    end
  end

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
    previous_executor = Application.get_env(:jido_sql, :query_executor)
    Application.put_env(:jido_sql, :query_executor, TestQueryExecutor)

    on_exit(fn ->
      if previous_executor do
        Application.put_env(:jido_sql, :query_executor, previous_executor)
      else
        Application.delete_env(:jido_sql, :query_executor)
      end
    end)

    {:ok, workspace} = Workspaces.create_workspace(%{"name" => "Artifact Action Test"})

    {:ok, session} =
      Workspaces.create_agent_session(workspace.id, %{
        "agent_profile_id" => "general_agent",
        "display_name" => "Operator"
      })

    %{workspace: workspace, session: session}
  end

  describe "artifact actions" do
    test "reexecute_query loads a SQL result through the demo action module", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      sql_results = [
        %{
          sql: "SELECT name, role FROM agents",
          label: "Agent list",
          row_count: 1,
          column_count: 2
        }
      ]

      Phoenix.PubSub.broadcast!(
        Murmur.PubSub,
        Topics.agent_artifacts(workspace.id, session.id),
        artifact_signal(session.id, "sql_results", envelope(sql_results, session.id))
      )

      view
      |> element(~s|button[phx-click="reexecute_query"][phx-value-index="0"]|)
      |> render_click()

      html = render(view)
      assert html =~ "Refresh"
      assert html =~ "Neo"
      assert html =~ "agent"
      assert html =~ "Showing 1 rows"
    end

    test "reexecute_query stores executor errors on the artifact", %{
      conn: conn,
      workspace: workspace,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      sql_results = [
        %{
          sql: "BROKEN",
          label: "Broken query",
          row_count: 0,
          column_count: 0
        }
      ]

      Phoenix.PubSub.broadcast!(
        Murmur.PubSub,
        Topics.agent_artifacts(workspace.id, session.id),
        artifact_signal(session.id, "sql_results", envelope(sql_results, session.id))
      )

      view
      |> element(~s|button[phx-click="reexecute_query"][phx-value-index="0"]|)
      |> render_click()

      html = render(view)
      assert html =~ "boom"
    end
  end
end
