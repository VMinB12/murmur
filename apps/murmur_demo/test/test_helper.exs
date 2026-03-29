# Restore config to demo app's modules (package test helpers may override these)
Application.put_env(:jido_murmur, :repo, Murmur.Repo)
Application.put_env(:jido_murmur, :pubsub, Murmur.PubSub)
Application.put_env(:jido_murmur, :jido_mod, Murmur.Jido)
Application.put_env(:jido_murmur, :otp_app, :murmur_demo)
Application.put_env(:jido_tasks, :repo, Murmur.Repo)
Application.put_env(:jido_tasks, :pubsub, Murmur.PubSub)

Mox.defmock(JidoMurmur.LLM.Mock, for: JidoMurmur.LLM)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Murmur.Repo, :manual)
