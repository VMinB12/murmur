defmodule JidoMurmur.Config do
  @moduledoc """
  Startup configuration validation for jido_murmur.

  Call `validate!/0` at supervisor init to ensure all required
  configuration keys are present before the application starts.
  """

  @required_keys [:repo, :pubsub, :jido_mod, :otp_app]

  @spec validate!() :: :ok | no_return()
  def validate! do
    missing =
      Enum.filter(@required_keys, fn key ->
        Application.get_env(:jido_murmur, key) == nil
      end)

    if missing != [] do
      keys_list = Enum.map_join(missing, "\n    - ", &inspect/1)

      raise """
      Missing required configuration for :jido_murmur

        The following keys are not configured:
          - #{keys_list}

        Add to your config/config.exs:

          config :jido_murmur,
            repo: MyApp.Repo,
            pubsub: MyApp.PubSub,
            jido_mod: MyApp.Jido,
            otp_app: :my_app
      """
    end

    :ok
  end
end
