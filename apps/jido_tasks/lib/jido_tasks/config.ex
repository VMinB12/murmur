defmodule JidoTasks.Config do
  @moduledoc """
  Startup configuration validation for jido_tasks.

  Call `validate!/0` at supervisor init to ensure all required
  configuration keys are present before the application starts.
  """

  @required_keys [:repo, :pubsub]

  @spec validate!() :: :ok | no_return()
  def validate! do
    missing =
      Enum.filter(@required_keys, fn key ->
        Application.get_env(:jido_tasks, key) == nil
      end)

    if missing != [] do
      keys_list = Enum.map_join(missing, "\n    - ", &inspect/1)

      raise """
      Missing required configuration for :jido_tasks

        The following keys are not configured:
          - #{keys_list}

        Add to your config/config.exs:

          config :jido_tasks,
            repo: MyApp.Repo,
            pubsub: MyApp.PubSub
      """
    end

    :ok
  end
end
