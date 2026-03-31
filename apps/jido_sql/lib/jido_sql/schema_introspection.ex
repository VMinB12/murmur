defmodule JidoSql.SchemaIntrospection do
  @moduledoc "Reads the database schema at startup and produces a text summary for LLM instructions."

  alias Ecto.Adapters.SQL, as: EctoSQL
  alias Postgrex.Error, as: PostgrexError

  @schema_query """
  SELECT table_name, column_name, data_type
  FROM information_schema.columns
  WHERE table_schema = 'public'
  ORDER BY table_name, ordinal_position
  """

  @doc """
  Reads the public schema from the given Ecto Repo and returns a human-readable summary.
  """
  @spec describe_schema(module()) :: {:ok, String.t()} | {:error, String.t()}
  def describe_schema(repo) do
    case EctoSQL.query(repo, @schema_query, []) do
      {:ok, %{rows: []}} ->
        {:ok, "(no tables found in public schema)"}

      {:ok, %{rows: rows}} ->
        {:ok, format_schema(rows)}

      {:error, %PostgrexError{} = err} ->
        {:error, Exception.message(err)}

      {:error, err} when is_exception(err) ->
        {:error, Exception.message(err)}

      {:error, err} ->
        {:error, inspect(err)}
    end
  end

  @doc "Like `describe_schema/1` but raises on failure."
  @spec describe_schema!(module()) :: String.t()
  def describe_schema!(repo) do
    case describe_schema(repo) do
      {:ok, text} -> text
      {:error, reason} -> raise "Schema introspection failed: #{reason}"
    end
  end

  @doc """
  Loads the schema into `:persistent_term` for zero-cost reads by the request transformer.

  Returns `{:ok, {table_count, column_count}}` on success.
  """
  @spec cache_schema(module()) :: {:ok, {non_neg_integer(), non_neg_integer()}} | {:error, String.t()}
  def cache_schema(repo) do
    case describe_schema(repo) do
      {:ok, text} ->
        :persistent_term.put({JidoSql, :schema}, text)
        {tables, columns} = count_schema(text)
        {:ok, {tables, columns}}

      {:error, _} = error ->
        error
    end
  end

  @doc "Returns the cached schema text, or nil if not loaded."
  @spec cached_schema() :: String.t() | nil
  def cached_schema do
    :persistent_term.get({JidoSql, :schema}, nil)
  end

  defp count_schema(text) do
    lines = String.split(text, "\n")
    tables = Enum.count(lines, &String.starts_with?(&1, "Table: "))
    columns = Enum.count(lines, &String.starts_with?(&1, "  - "))
    {tables, columns}
  end

  defp format_schema(rows) do
    rows
    |> Enum.group_by(&Enum.at(&1, 0))
    |> Enum.sort_by(fn {table, _} -> table end)
    |> Enum.map_join("\n\n", fn {table, cols} ->
      columns = Enum.map_join(cols, "\n", fn [_, col, type] -> "  - #{col} (#{type})" end)
      "Table: #{table}\n#{columns}"
    end)
  end
end
