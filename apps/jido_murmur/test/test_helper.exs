ExUnit.start()

# Set sandbox mode if the configured Repo is available (umbrella context)
try do
  Ecto.Adapters.SQL.Sandbox.mode(JidoMurmur.repo(), :manual)
rescue
  _ -> :ok
end
