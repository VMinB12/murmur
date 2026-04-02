ExUnit.start()

if Process.whereis(JidoSql.Repo) do
  Ecto.Adapters.SQL.Sandbox.mode(JidoSql.Repo, :manual)
end
