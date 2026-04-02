defmodule JidoSql do
  @moduledoc "SQL agent plugin — connects to an external database for natural-language querying."

  @doc "Returns the configured Ecto Repo module for the SQL agent target database."
  @spec repo() :: module()
  def repo do
    Application.fetch_env!(:jido_sql, :repo)
  end

  @doc "Returns the query executor module used by SQL tools."
  @spec query_executor() :: module()
  def query_executor do
    Application.get_env(:jido_sql, :query_executor, JidoSql.QueryExecutor)
  end
end
