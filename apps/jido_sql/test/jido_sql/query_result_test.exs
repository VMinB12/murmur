defmodule JidoSql.QueryResultTest do
  use ExUnit.Case, async: true

  alias JidoSql.QueryResult

  test "builds a typed query result struct" do
    result = QueryResult.new(["id", "name"], [["1", "Ada"]], 1)

    assert %QueryResult{} = result
    assert result.columns == ["id", "name"]
    assert result.rows == [["1", "Ada"]]
    assert result.total_rows == 1
  end

  test "enforces required keys" do
    assert_raise ArgumentError, fn ->
      struct!(QueryResult, columns: ["id"], rows: [["1"]])
    end
  end
end
