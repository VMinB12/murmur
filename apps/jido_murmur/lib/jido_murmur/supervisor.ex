defmodule JidoMurmur.Supervisor do
  @moduledoc """
  Supervision tree for jido_murmur package processes.

  Manages `JidoMurmur.TableOwner` which owns ETS tables for PendingQueue and Runner.

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
    children = [
      JidoMurmur.TableOwner
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
