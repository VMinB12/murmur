ExUnit.start()

# When running jido_murmur tests in isolation, Murmur.Repo won't be available.
# Use the test-specific JidoMurmur.TestRepo and override the config.
repo =
  try do
    JidoMurmur.repo()
  rescue
    _ -> nil
  end

repo =
  if repo && Code.ensure_loaded?(repo) do
    repo
  else
    Application.put_env(:jido_murmur, :repo, JidoMurmur.TestRepo)
    JidoMurmur.TestRepo
  end

# When running in isolation, configure test-specific Jido and PubSub
jido_mod =
  try do
    JidoMurmur.jido_mod()
  rescue
    _ -> nil
  end

unless jido_mod && Code.ensure_loaded?(jido_mod) do
  Application.put_env(:jido_murmur, :jido_mod, JidoMurmur.TestJido)
  Application.put_env(:jido_murmur, :otp_app, :jido_murmur)
end

pubsub =
  try do
    JidoMurmur.pubsub()
  rescue
    _ -> nil
  end

unless pubsub && Process.whereis(pubsub) do
  Application.put_env(:jido_murmur, :pubsub, JidoMurmur.TestPubSub)
end

# Start PubSub for tests
case Phoenix.PubSub.Supervisor.start_link(name: JidoMurmur.TestPubSub) do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
end

# Start the repo
case repo.start_link() do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
end

Ecto.Adapters.SQL.Sandbox.mode(repo, :manual)

# Ensure profiles only contain modules available in jido_murmur's test context.
# When running in the umbrella, config.exs may set profiles to demo-app modules
# (e.g. Murmur.Agents.Profiles.GeneralAgent) that aren't compiled here.
profiles = Application.get_env(:jido_murmur, :profiles, [])

valid_profiles =
  Enum.filter(profiles, fn mod ->
    Code.ensure_loaded?(mod) && function_exported?(mod, :name, 0)
  end)

Application.put_env(:jido_murmur, :profiles, valid_profiles)

# Start TestJido if needed
jido_mod = JidoMurmur.jido_mod()

if Code.ensure_loaded?(jido_mod) && function_exported?(jido_mod, :start_link, 1) do
  case jido_mod.start_link([]) do
    {:ok, _} -> :ok
    {:error, {:already_started, _}} -> :ok
    _ -> :ok
  end
end
