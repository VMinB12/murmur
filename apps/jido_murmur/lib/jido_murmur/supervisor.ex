defmodule JidoMurmur.Supervisor do
  @moduledoc """
  Supervision tree for jido_murmur package processes.

  Manages shared ETS state plus ingress coordination infrastructure.

  Add to your application supervision tree:

      children = [
        {JidoMurmur.Supervisor, []},
        ...
      ]
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    JidoMurmur.Config.validate!()

    children = [
      JidoMurmur.TableOwner,
      {Registry, keys: :unique, name: JidoMurmur.Ingress.registry_name()},
      {DynamicSupervisor, strategy: :one_for_one, name: JidoMurmur.Ingress.supervisor_name()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
