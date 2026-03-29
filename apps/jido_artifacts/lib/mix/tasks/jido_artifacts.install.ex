defmodule Mix.Tasks.JidoArtifacts.Install do
  @moduledoc """
  Installs jido_artifacts configuration into the host application.

  Adds `config :jido_artifacts, pubsub: {App}.PubSub` to config.

  ## Usage

      mix jido_artifacts.install

  This is a placeholder for future Igniter-based installation (see 004-igniter-adoption).
  """

  use Mix.Task

  @shortdoc "Installs jido_artifacts configuration"

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("""
    Add the following to your config/config.exs:

        config :jido_artifacts,
          pubsub: MyApp.PubSub

    Replace MyApp.PubSub with your application's PubSub module.
    """)
  end
end
