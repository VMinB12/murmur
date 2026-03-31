defmodule JidoSql.Repo do
  @moduledoc "Ecto Repo for the SQL agent target database."
  use Ecto.Repo, otp_app: :jido_sql, adapter: Ecto.Adapters.Postgres
end
