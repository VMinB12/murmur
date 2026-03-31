defmodule JidoSql.Tools.Display do
  @moduledoc """
  Validates a SQL query and emits a deferred artifact for the data panel.

  The artifact stores only the SQL text — results are fetched dynamically
  by the renderer when the user views the tab.
  """

  use Jido.Action,
    name: "sql_display",
    description:
      "Run a SQL query and display the full results to the user as a table in the data panel. " <>
        "Use this when you have the final answer ready and want to show it to the user.",
    schema: [
      sql_query: [type: :string, required: true, doc: "The SQL query to execute and display"]
    ]

  alias JidoArtifacts.{Artifact, Merge}

  @impl true
  def run(params, ctx) do
    case JidoSql.QueryExecutor.execute(JidoSql.repo(), params.sql_query) do
      {:ok, result} ->
        artifact_data = %{
          sql: params.sql_query,
          label: derive_label(params.sql_query),
          row_count: result.total_rows,
          column_count: length(result.columns)
        }

        artifact_directive =
          Artifact.emit(ctx, "sql_results", artifact_data, merge: &Merge.append/2)

        {:ok,
         %{result: "Query result displayed to user (#{result.total_rows} rows)"},
         artifact_directive}

      {:error, message} ->
        {:error, message}
    end
  end

  defp derive_label(sql) do
    # Extract a readable label from the SQL query
    sql
    |> String.trim()
    |> String.slice(0, 80)
    |> then(fn label ->
      if String.length(sql) > 80, do: label <> "...", else: label
    end)
  end
end
