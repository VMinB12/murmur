defmodule JidoArtifacts do
  @moduledoc """
  Artifact system for Jido agents.

  Provides helpers for emitting, merging, storing, and broadcasting
  structured data artifacts produced by tool actions.

  ## Configuration

      config :jido_artifacts,
        pubsub: MyApp.PubSub
  """

  @doc "Returns the configured Phoenix.PubSub module."
  def pubsub do
    Application.fetch_env!(:jido_artifacts, :pubsub)
  end
end
