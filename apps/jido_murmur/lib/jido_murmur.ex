defmodule JidoMurmur do
  @moduledoc """
  Multi-agent orchestration for Jido.

  Configuration accessors for the consumer's Repo, PubSub, Jido module, and OTP app.

  ## Configuration

      config :jido_murmur,
        repo: MyApp.Repo,
        pubsub: MyApp.PubSub,
        jido_mod: MyApp.Jido,
        otp_app: :my_app
  """
end
