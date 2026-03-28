defmodule JidoMurmur do
  @moduledoc """
  Multi-agent orchestration for Jido.

  Configuration accessors for the consumer's Repo, PubSub, Jido module, and OTP app.

  ## Configuration

      config :jido_murmur,
        repo: MyApp.Repo,
        pubsub: MyApp.PubSub,
        jido_mod: MyApp.Jido,
        otp_app: :my_app,
        profiles: [MyApp.Agents.AssistantAgent],
        authorize: nil,
        artifact_renderers: %{}
  """

  @doc "Returns the consumer's Ecto.Repo module."
  def repo do
    Application.fetch_env!(:jido_murmur, :repo)
  end

  @doc "Returns the consumer's Phoenix.PubSub module."
  def pubsub do
    Application.fetch_env!(:jido_murmur, :pubsub)
  end

  @doc "Returns the consumer's `use Jido` module."
  def jido_mod do
    Application.fetch_env!(:jido_murmur, :jido_mod)
  end

  @doc "Returns the consumer's OTP application name."
  def otp_app do
    Application.fetch_env!(:jido_murmur, :otp_app)
  end
end
