defmodule JidoSql.QueryResult do
  @moduledoc """
  Canonical query execution result returned by `JidoSql.QueryExecutor`.
  """

  @enforce_keys [:columns, :rows, :total_rows]
  defstruct [:columns, :rows, :total_rows]

  @type t :: %__MODULE__{
          columns: [String.t()],
          rows: [[term()]],
          total_rows: non_neg_integer()
        }

  @spec new([String.t()], [[term()]], non_neg_integer()) :: t()
  def new(columns, rows, total_rows)
      when is_list(columns) and is_list(rows) and is_integer(total_rows) and total_rows >= 0 do
    %__MODULE__{columns: columns, rows: rows, total_rows: total_rows}
  end
end
