defmodule JidoMurmur.Config do
  @moduledoc """
  Startup configuration validation for jido_murmur.

  Call `validate!/0` at supervisor init to ensure all required
  configuration keys are present before the application starts.
  """

  @default_tell_hop_limit 5
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

    validate_optional_non_negative_integer!(:tell_hop_limit)

    :ok
  end

  @spec tell_hop_limit() :: non_neg_integer()
  def tell_hop_limit do
    case Application.get_env(:jido_murmur, :tell_hop_limit, @default_tell_hop_limit) do
      value when is_integer(value) and value >= 0 -> value
      _ ->
        raise "invalid :jido_murmur :tell_hop_limit configuration; expected a non-negative integer"
    end
  end

  defp validate_optional_non_negative_integer!(key) do
    case Application.get_env(:jido_murmur, key, :unset) do
      :unset -> :ok
      value when is_integer(value) and value >= 0 -> :ok
      _ -> raise "invalid :jido_murmur #{inspect(key)} configuration; expected a non-negative integer"
    end
  end
end
