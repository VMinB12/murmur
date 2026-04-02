defmodule JidoSql.QueryExecutorTest do
  use ExUnit.Case, async: true

  alias JidoSql.QueryExecutor
  alias JidoSql.QueryResult

  test "truncate/3 preserves total row metadata while slicing rows and columns" do
    result =
      QueryResult.new(
        ["id", "name", "role"],
        [
          ["1", "Ada", "admin"],
          ["2", "Grace", "user"],
          ["3", "Linus", "user"]
        ],
        3
      )

    truncated = QueryExecutor.truncate(result, 2, 2)

    assert truncated.columns == ["id", "name"]
    assert truncated.rows == [["1", "Ada"], ["2", "Grace"]]
    assert truncated.total_rows == 3
    assert truncated.total_columns == 3
    assert truncated.truncated
  end

  test "format_text_table/1 renders empty tables clearly" do
    result = %{columns: ["id", "name"], rows: [], total_rows: 0, truncated: false, total_columns: 2}

    assert QueryExecutor.format_text_table(result) == "id | name\n\n(no rows)"
  end

  test "format_text_table/1 includes truncation summary" do
    result = %{
      columns: ["id", "name"],
      rows: [["1", "Ada"], ["2", "Grace"]],
      total_rows: 5,
      truncated: true,
      total_columns: 4
    }

    formatted = QueryExecutor.format_text_table(result)

    assert formatted =~ "id | name"
    assert formatted =~ "1  | Ada"
    assert formatted =~ "Showing 2 of 5 rows"
    assert formatted =~ "2 of 4 columns"
    assert formatted =~ "Results truncated."
  end
end
