# Restore config to demo app's modules (package test helpers may override these)
Application.put_env(:jido_murmur, :repo, Murmur.Repo)
Application.put_env(:jido_murmur, :pubsub, Murmur.PubSub)
Application.put_env(:jido_murmur, :jido_mod, Murmur.Jido)
Application.put_env(:jido_murmur, :otp_app, :murmur_demo)
Application.put_env(:jido_murmur, :llm_adapter, Murmur.LLM.MockBehaviour)
Application.put_env(:jido_murmur, :skip_hibernate, true)
Application.put_env(:jido_murmur, :profiles, [
  Murmur.Agents.Profiles.GeneralAgent,
  Murmur.Agents.Profiles.ArxivAgent
])
Application.put_env(:jido_tasks, :repo, Murmur.Repo)
Application.put_env(:jido_tasks, :pubsub, Murmur.PubSub)

# Clear stale ETS state from prior test apps (jido_murmur tests create tables directly)
for table <- [:jido_murmur_active_runners] do
  if :ets.whereis(table) != :undefined do
    :ets.delete_all_objects(table)
  end
end

Mox.defmock(Murmur.LLM.MockBehaviour, for: JidoMurmur.LLM)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Murmur.Repo, :manual)
