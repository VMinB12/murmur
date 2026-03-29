ExUnit.start()

# Configure jido_tasks repo for isolated package tests
repo =
  try do
    JidoTasks.repo()
  rescue
    _ -> nil
  end

repo =
  if repo && Code.ensure_loaded?(repo) do
    repo
  else
    Application.put_env(:jido_tasks, :repo, JidoTasks.TestRepo)
    JidoTasks.TestRepo
  end

# Configure PubSub
pubsub =
  try do
    JidoTasks.pubsub()
  rescue
    _ -> nil
  end

unless pubsub && Process.whereis(pubsub) do
  Application.put_env(:jido_tasks, :pubsub, JidoTasks.TestPubSub)
end

# Also configure jido_murmur repo/pubsub to use jido_tasks test infrastructure
Application.put_env(:jido_murmur, :repo, JidoTasks.TestRepo)
Application.put_env(:jido_murmur, :pubsub, JidoTasks.TestPubSub)
Application.put_env(:jido_murmur, :jido_mod, JidoTasks.TestJido)
Application.put_env(:jido_murmur, :otp_app, :jido_tasks)

# Start PubSub for tests
case Phoenix.PubSub.Supervisor.start_link(name: JidoTasks.TestPubSub) do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
end

# Start the repo
case repo.start_link() do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
end

Ecto.Adapters.SQL.Sandbox.mode(repo, :manual)
