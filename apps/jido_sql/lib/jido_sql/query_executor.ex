defmodule JidoSql.QueryExecutor do
  @moduledoc "Executes raw SQL queries with timeout, truncation, and text formatting."

  alias Ecto.Adapters.SQL, as: EctoSQL
  alias Postgrex.Error, as: PostgrexError

  @default_timeout 15_000
  @default_max_rows 50
  @default_max_cols 20

  @doc """
  Executes a raw SQL query against the given Ecto Repo.

  Returns `{:ok, %{columns: [...], rows: [[...]], total_rows: n}}` on success,
  or `{:error, message}` on failure.

  ## Options

    * `:timeout` — query timeout in ms (default: #{@default_timeout})
  """
  @spec execute(module(), String.t(), keyword()) ::
          {:ok, %{columns: [String.t()], rows: [[term()]], total_rows: non_neg_integer()}}
          | {:error, String.t()}
  def execute(repo, sql, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    case EctoSQL.query(repo, sql, [], timeout: timeout) do
      {:ok, %{columns: cols, rows: rows, num_rows: count}} ->
        {:ok, %{columns: cols, rows: sanitize_rows(rows), total_rows: count}}

      {:error, %PostgrexError{} = err} ->
        {:error, Exception.message(err)}

      {:error, err} when is_exception(err) ->
        {:error, Exception.message(err)}

      {:error, err} ->
        {:error, inspect(err)}
    end
  end

  @doc """
  Truncates a query result to fit within row and column limits.

  Returns a map with `:truncated` flag indicating whether truncation was applied.
  """
  @spec truncate(map(), non_neg_integer(), non_neg_integer()) :: map()
  def truncate(result, max_rows \\ @default_max_rows, max_cols \\ @default_max_cols) do
    total_columns = length(result.columns)
    cols = Enum.take(result.columns, max_cols)
    rows = result.rows |> Enum.take(max_rows) |> Enum.map(&Enum.take(&1, max_cols))
    truncated = result.total_rows > max_rows or total_columns > max_cols

    %{
      columns: cols,
      rows: rows,
      truncated: truncated,
      total_rows: result.total_rows,
      total_columns: total_columns
    }
  end

  @doc """
  Formats a truncated result as a pipe-separated text table for LLM consumption.
  """
  @spec format_text_table(map()) :: String.t()
  def format_text_table(%{columns: [], rows: [], total_rows: 0}) do
    "(no rows)"
  end

  def format_text_table(%{columns: columns, rows: [], total_rows: 0}) do
    Enum.join(columns, " | ") <> "\n\n(no rows)"
  end

  def format_text_table(%{columns: columns, rows: rows} = result) do
    # Calculate column widths
    all_values = [columns | Enum.map(rows, fn row -> Enum.map(row, &to_string_safe/1) end)]

    widths =
      columns
      |> Enum.with_index()
      |> Enum.map(fn {_, i} ->
        all_values
        |> Enum.map(fn row -> row |> Enum.at(i, "") |> String.length() end)
        |> Enum.max()
        |> min(40)
      end)

    # Format header
    header = format_row(columns, widths)
    separator = Enum.map_join(widths, "-+-", &String.duplicate("-", &1))

    # Format data rows
    data_rows =
      rows
      |> Enum.map(fn row -> row |> Enum.map(&to_string_safe/1) |> format_row(widths) end)

    # Build table
    table = [header, separator | data_rows] |> Enum.join("\n")

    # Add summary
    summary = row_summary(result)
    table <> "\n\n" <> summary
  end

  defp format_row(values, widths) do
    Enum.zip(values, widths)
    |> Enum.map_join(" | ", fn {val, width} -> String.pad_trailing(to_string_safe(val), width) end)
  end

  defp row_summary(%{truncated: true, total_rows: total, total_columns: total_cols} = result) do
    shown_rows = length(result.rows)
    shown_cols = length(result.columns)
    parts = []

    parts =
      if total > shown_rows do
        parts ++ ["Showing #{shown_rows} of #{format_number(total)} rows"]
      else
        parts ++ ["#{format_number(total)} rows returned"]
      end

    parts =
      if total_cols > shown_cols do
        parts ++ ["#{shown_cols} of #{total_cols} columns"]
      else
        parts
      end

    Enum.join(parts, " (") <>
      if(total_cols > shown_cols or total > shown_rows,
        do: "). Results truncated.",
        else: "."
      )
  end

  defp row_summary(%{total_rows: total}) do
    "#{format_number(total)} rows returned."
  end

  defp sanitize_rows(rows) do
    Enum.map(rows, fn row -> Enum.map(row, &to_string_safe/1) end)
  end

  defp to_string_safe(nil), do: "NULL"
  defp to_string_safe(val) when is_binary(val) do
    if String.valid?(val), do: val, else: inspect(val)
  end
  defp to_string_safe(val), do: inspect(val)

  defp format_number(n) when n >= 1_000 do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join(Enum.reverse(&1)))
  end

  defp format_number(n), do: Integer.to_string(n)
end
