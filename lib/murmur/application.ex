defmodule Murmur.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MurmurWeb.Telemetry,
      Murmur.Repo,
      {DNSCluster, query: Application.get_env(:murmur, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Murmur.PubSub},
      # Start a worker by calling: Murmur.Worker.start_link(arg)
      # {Murmur.Worker, arg},
      # Start to serve requests, typically the last entry
      MurmurWeb.Endpoint,
      Murmur.Jido
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Murmur.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MurmurWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
