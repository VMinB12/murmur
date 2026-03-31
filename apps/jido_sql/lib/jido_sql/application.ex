defmodule JidoSql.Application do
  @moduledoc false
  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    children =
      if repo_configured?() do
        [JidoSql.Repo]
      else
        Logger.warning("JidoSql: SQL_AGENT_DATABASE_URL not set — SQL agent disabled")
        []
      end

    opts = [strategy: :one_for_one, name: JidoSql.Supervisor]
    result = Supervisor.start_link(children, opts)

    if repo_configured?() do
      case JidoSql.SchemaIntrospection.cache_schema(JidoSql.Repo) do
        {:ok, {table_count, column_count}} ->
          Logger.info(
            "JidoSql: Connected to target database. Schema loaded: #{table_count} tables, #{column_count} columns."
          )

        {:error, reason} ->
          Logger.error("JidoSql: Failed to load schema — #{reason}")
      end
    end

    result
  end

  defp repo_configured? do
    config = Application.get_env(:jido_sql, JidoSql.Repo, [])
    Keyword.has_key?(config, :url) or Keyword.has_key?(config, :hostname)
  end
end
