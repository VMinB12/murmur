defmodule JidoSql.Tools.Query do
  @moduledoc "Executes an exploratory SQL query and returns a truncated text preview for the LLM."

  use Jido.Action,
    name: "sql_query",
    description:
      "Run a SQL query against the database and return a truncated preview of the results. " <>
        "Use this to explore data and refine queries before displaying final results.",
    schema: [
      sql_query: [type: :string, required: true, doc: "The SQL query to execute"]
    ]

  alias JidoSql.QueryExecutor

  @impl true
  def run(params, _ctx) do
    max_rows = Application.get_env(:jido_sql, :max_rows, 50)
    max_cols = Application.get_env(:jido_sql, :max_columns, 20)

    case QueryExecutor.execute(JidoSql.repo(), params.sql_query) do
      {:ok, result} ->
        formatted =
          result
          |> QueryExecutor.truncate(max_rows, max_cols)
          |> QueryExecutor.format_text_table()

        {:ok, %{result: formatted}}

      {:error, message} ->
        {:error, message}
    end
  end
end
