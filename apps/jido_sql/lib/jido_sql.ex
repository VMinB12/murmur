defmodule JidoSql do
  @moduledoc "SQL agent plugin — connects to an external database for natural-language querying."

  @doc "Returns the configured Ecto Repo module for the SQL agent target database."
  def repo do
    Application.fetch_env!(:jido_sql, :repo)
  end
end
