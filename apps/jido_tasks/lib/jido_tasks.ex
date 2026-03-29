defmodule JidoTasks do
  @moduledoc """
  Task management tools for Jido agents.

  ## Configuration

      config :jido_tasks,
        repo: MyApp.Repo,
        pubsub: MyApp.PubSub
  """

  @doc "Returns the consumer's Ecto.Repo module."
  def repo do
    Application.fetch_env!(:jido_tasks, :repo)
  end

  @doc "Returns the consumer's Phoenix.PubSub module."
  def pubsub do
    Application.fetch_env!(:jido_tasks, :pubsub)
  end
end
