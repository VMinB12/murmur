defmodule Murmur.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias JidoMurmur.Telemetry.JidoAITracer
  alias JidoMurmur.Telemetry.ReqLLMTracer

  @impl true
  def start(_type, _args) do
    if Application.get_env(:murmur_demo, :log_filter, false) do
      :logger.add_handler_filter(:default, :drop_verbose, {&Murmur.LogFilter.filter/2, []})
    end

    Jido.Telemetry.setup()
  JidoAITracer.attach()
    ReqLLMTracer.attach()
    JidoTasks.Config.validate!()

    children = [
      MurmurWeb.Telemetry,
      Murmur.Repo,
      {DNSCluster, query: Application.get_env(:murmur_demo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Murmur.PubSub},
      JidoMurmur.Supervisor,
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
