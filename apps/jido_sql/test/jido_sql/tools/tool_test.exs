defmodule JidoSql.Tools.ToolTest do
  use ExUnit.Case, async: false

  alias JidoSql.QueryResult
  alias JidoSql.Tools.Display
  alias JidoSql.Tools.Query

  defmodule FakeSuccessExecutor do
    alias JidoSql.QueryResult

    def execute(_repo, _sql) do
      {:ok, QueryResult.new(["id", "name"], [["1", "Ada"], ["2", "Grace"]], 2)}
    end

    def truncate(%QueryResult{} = _result, _max_rows, _max_cols) do
      %{
        columns: ["id", "name"],
        rows: [["1", "Ada"], ["2", "Grace"]],
        truncated: false,
        total_rows: 2,
        total_columns: 2
      }
    end

    def format_text_table(_result) do
      "id | name\n-- + ----\n1 | Ada\n2 | Grace"
    end
  end

  defmodule FakeErrorExecutor do
    def execute(_repo, _sql), do: {:error, "query failed"}
    def truncate(_result, _max_rows, _max_cols), do: raise("should not be called")
    def format_text_table(_result), do: raise("should not be called")
  end

  setup do
    {:ok, _} = Application.ensure_all_started(:jido_signal)

    original = Application.get_env(:jido_sql, :query_executor)
    original_repo = Application.get_env(:jido_sql, :repo)

    Application.put_env(:jido_sql, :repo, JidoSql.Repo)

    on_exit(fn ->
      restore_env(:query_executor, original)
      restore_env(:repo, original_repo)
    end)

    :ok
  end

  describe "Query.run/2" do
    test "formats truncated output from a typed query result" do
      Application.put_env(:jido_sql, :query_executor, FakeSuccessExecutor)

      assert {:ok, %{result: result}} = Query.run(%{sql_query: "SELECT * FROM users"}, %{})
      assert result =~ "id | name"
      assert result =~ "Ada"
    end

    test "returns executor errors unchanged" do
      Application.put_env(:jido_sql, :query_executor, FakeErrorExecutor)

      assert {:error, "query failed"} = Query.run(%{sql_query: "SELECT * FROM missing"}, %{})
    end
  end

  describe "Display.run/2" do
    test "emits a sql_results artifact from a typed query result" do
      Application.put_env(:jido_sql, :query_executor, FakeSuccessExecutor)

      ctx = %{state: %{__agent_id__: "sql-agent", artifacts: %{}}}

      assert {:ok, %{result: result}, %Jido.Agent.Directive.Emit{signal: signal}} =
               Display.run(%{sql_query: "SELECT * FROM users"}, ctx)

      assert result == "Query result displayed to user (2 rows)"
      assert signal.type == "artifact.sql_results"
      assert signal.data.mode == :merge
      assert signal.data.data.label == "SELECT * FROM users"
      assert signal.data.data.row_count == 2
      assert signal.data.data.column_count == 2
    end

    test "returns executor errors unchanged" do
      Application.put_env(:jido_sql, :query_executor, FakeErrorExecutor)

      assert {:error, "query failed"} = Display.run(%{sql_query: "SELECT * FROM missing"}, %{})
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:jido_sql, key)
  defp restore_env(key, value), do: Application.put_env(:jido_sql, key, value)
end
